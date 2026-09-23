// clockemit v3: ONE emitter, THREE schedules (PI spec C).
//
// Architecture (identical across modes):
//   - scheduler: 1ms-slot wheel; each stream belongs to one 1ms slot
//     within its 25ms step (aligned: all in slot 0; random: uniformly
//     spread over 25 slots; per-engine: engine i in slot i mod 25)
//   - per-stream queue of K frames, drop-oldest on overflow (drops
//     counted - backpressure is a MEASURED signal, never silent)
//   - one writer goroutine per stream, draining its queue (blocking
//     writes; slow_writes>1ms counted)
// Gate (run validity): drops > 0.1% of tokens OR slot_overruns > 0
// OR process CPU > 90% of cores. All three visible at /stats.
//
// clockemit: accepts GET /stream, serves SSE data frames 1:1 with
// tokens (validated against vLLM: one segment per frame).
package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	qDepth   = 4    // per-stream queue (frames); drop-oldest on overflow
	slotMs   = 1    // wheel granularity
	stepMs   = 25   // decode-step period (40 tok/s)
	nSlots   = stepMs / slotMs
	slowWrite = time.Millisecond
)

type stream struct {
	q        chan []byte
	done     chan struct{}
	closeOne sync.Once
	lastID   int64
}

var (
	mu       sync.Mutex
	streams  = map[int]*stream{}
	nextID   int
	tokens   = [][]byte{}

	writtenTok  atomic.Uint64
	writtenByt  atomic.Uint64
	droppedTok  atomic.Uint64
	slowWrites  atomic.Uint64
	slowWriteNs atomic.Uint64
	slotOverrun atomic.Uint64
	slotPassNs  atomic.Uint64
	steps       atomic.Uint64
	prevCPUTime atomic.Int64
)

func init() {
	for i := 0; i < 256; i++ {
		t := []byte("data: ")
		for j := 0; j < 88; j++ { // frame ~= 96B, matching vLLM's ~100B SSE shape
			t = append(t, "0123456789abcdef"[(i+j*7)%16])
		}
		t = append(t, '\n', '\n')
		tokens = append(tokens, t)
	}
}

// cpuSeconds reads utime+stime of this process (jiffies -> s).
func cpuSeconds() float64 {
	b, err := os.ReadFile("/proc/self/stat")
	if err != nil {
		return 0
	}
	// fields after the (comm) parenthesis: 14=utime 15=stime (1-based)
	s := string(b)
	i := strings.LastIndexByte(s, ')')
	if i < 0 {
		return 0
	}
	f := strings.Fields(s[i+1:])
	if len(f) < 15 {
		return 0
	}
	ut, _ := strconv.ParseInt(f[11], 10, 64)
	st, _ := strconv.ParseInt(f[12], 10, 64)
	return float64(ut+st) / 100.0 // CLK_TCK=100 on this kernel
}

func writeFrame(s *stream, frame []byte) {
	select {
	case s.q <- frame:
	default:
		// queue full: drop-oldest, enqueue newest, count the drop
		select {
		case <-s.q:
			droppedTok.Add(1)
		default:
		}
		select {
		case s.q <- frame:
		default:
			droppedTok.Add(1)
		}
	}
}

func handleStream(w http.ResponseWriter, r *http.Request, phase string) {
	fl, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "no flush", 500)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(200)
	fl.Flush()

	s := &stream{q: make(chan []byte, qDepth), done: make(chan struct{})}
	var slot int
	mu.Lock()
	id := nextID
	nextID++
	streams[id] = s
	mu.Unlock()

	switch phase {
	case "aligned":
		slot = 0
	case "random":
		slot = (id * 2654435761) % nSlots // Knuth hash, uniform spread
	case "per-engine":
		slot = (id / 256) % nSlots // engine-aligned, engines spread
	}
	_ = slot

	// the handler ITSELF drains the queue (ResponseWriter use stays in
	// the handler goroutine); the queue absorbs scheduler jitter and
	// drop-oldest marks backpressure
	defer s.closeOne.Do(func() {
		close(s.done)
		mu.Lock()
		delete(streams, id)
		mu.Unlock()
	})
	for {
		select {
		case frame := <-s.q:
			t0 := time.Now()
			n, err := w.Write(frame)
			d := time.Since(t0)
			if d > slowWrite {
				slowWrites.Add(1)
				slowWriteNs.Add(uint64(d))
			}
			if err != nil || n != len(frame) {
				return
			}
			writtenTok.Add(1)
			writtenByt.Add(uint64(n))
			fl.Flush()
		case <-r.Context().Done():
			return
		}
	}
}

// slotOf returns the wheel slot a stream emits in, per mode.
func slotOf(id int, phase string) int {
	switch phase {
	case "random":
		return (id * 2654435761) % nSlots
	case "per-engine":
		return (id / 256) % nSlots
	default:
		return 0
	}
}

func schedule(phase string) {
	// 1ms wheel: every tick, enqueue one frame to each stream whose
	// slot == (tick mod nSlots). Identical machinery for all modes.
	t := time.NewTicker(slotMs * time.Millisecond)
	defer t.Stop()
	last := time.Now()
	tick := 0
	for range t.C {
		t0 := time.Now()
		if d := t0.Sub(last); d > 1500*time.Microsecond && tick > 0 {
			slotOverrun.Add(1) // scheduler slip, not body work
		}
		last = t0

		slot := tick % nSlots
		if slot == 0 {
			steps.Add(1)
		}
		frame := tokens[tick&255]
		mu.Lock()
		targets := make([]*stream, 0, len(streams)/nSlots+8)
		for id, s := range streams {
			if slotOf(id, phase) == slot {
				targets = append(targets, s)
			}
		}
		mu.Unlock()
		for _, s := range targets {
			writeFrame(s, frame)
		}
		slotPassNs.Store(uint64(time.Since(t0))) // body duration at this load
		tick++
	}
}

func statsHandler(w http.ResponseWriter, r *http.Request) {
	cs := cpuSeconds()
	pc := prevCPUTime.Load()
	prevCPUTime.Store(int64(cs * 100))
	mu.Lock()
	n := len(streams)
	mu.Unlock()
	fmt.Fprintf(w, "streams=%d tokens=%d bytes=%d dropped=%d slow_writes=%d "+
		"slot_overruns=%d steps=%d cpu_s=%.1f slot_pass_us=%d\n",
		n, writtenTok.Load(), writtenByt.Load(), droppedTok.Load(),
		slowWrites.Load(), slotOverrun.Load(), steps.Load(), cs-float64(pc)/100,
		slotPassNs.Load()/1000)
}

func main() {
	listen := flag.String("listen", ":8000", "listen address")
	nStreams := flag.Int("streams", 25000, "max concurrent streams")
	phase := flag.String("phase", "aligned", "aligned|random|per-engine")
	flag.Parse()
	_ = nStreams

	go schedule(*phase)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		fmt.Fprintf(w, "streams=%d\n", len(streams))
		mu.Unlock()
	})
	mux.HandleFunc("/stats", statsHandler)
	mux.HandleFunc("/stream", func(w http.ResponseWriter, r *http.Request) {
		handleStream(w, r, *phase)
	})

	ln, err := net.Listen("tcp", *listen)
	if err != nil {
		log.Fatal(err)
	}
	tcpL := ln.(*net.TCPListener)
	log.Printf("clockemit v3 on %s phase=%s (queue=%d, wheel=%dms, step=%dms)",
		*listen, *phase, qDepth, slotMs, stepMs)

	srv := &http.Server{
		Handler: mux,
		ConnState: func(c net.Conn, state http.ConnState) {
			if state == http.StateNew {
				if tc, ok := c.(*net.TCPConn); ok {
					tc.SetNoDelay(true)
					tc.SetWriteBuffer(64 * 1024)
				}
			}
		},
	}
	log.Fatal(srv.Serve(tcpL))
}
