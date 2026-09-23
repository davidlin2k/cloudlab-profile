// clockemit: step-clock SSE emitter (vLLM-shaped token streaming).
//
// Modes:
//   aligned    - one shared tick; every stream gets a chunk every T
//   random     - per-stream ticker with a random offset in [0,T)
//   per-engine - streams grouped in engines of 256; each engine
//                aligned internally, engines at random phases
//
// TCP_NODELAY on every connection. Ticks are timed; a write pass
// taking > 90% of T counts as an overrun (invalid run) at /stats.
package main

import (
	"flag"
	"fmt"
	"math/rand"
	"net"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

var (
	nStreams = flag.Int("streams", 10000, "max concurrent streams")
	period   = flag.Int("period", 25, "step period ms")
	phase    = flag.String("phase", "aligned", "aligned|random|per-engine")
	chunk    = flag.Int("chunk", 100, "token chunk bytes")
	engSize  = flag.Int("engine", 256, "streams per engine (per-engine mode)")
	listen   = flag.String("listen", ":8000", "listen addr")
)

type stream struct {
	w     http.ResponseWriter
	flush http.Flusher
	done  chan struct{}
	engID int
}

var (
	mu      sync.Mutex
	streams = make(map[int]*stream)
	nextID  int
	sentTok atomic.Uint64
	sentByt atomic.Uint64
	overrun atomic.Uint64
)

func token() []byte {
	t := make([]byte, *chunk)
	for i := range t {
		t[i] = byte('a' + (i+int(sentTok.Load()))%26)
	}
	return t
}

func writeFrame(s *stream, frame []byte) bool {
	select {
	case <-s.done:
		return false
	default:
	}
	if _, err := s.w.Write(frame); err != nil {
		close(s.done)
		return false
	}
	s.flush.Flush()
	return true
}

func passTimer(t0 time.Time) {
	if d := time.Since(t0); d > time.Duration(*period)*time.Millisecond*9/10 {
		overrun.Add(1)
	}
}

// engine goroutines: one ticker per engine (per-engine mode)
var engOnce sync.Map // engID -> started

func runEngine(engID int) {
	ph := time.Duration(rand.Int63n(int64(*period))) * time.Millisecond
	time.Sleep(ph)
	t := time.NewTicker(time.Duration(*period) * time.Millisecond)
	defer t.Stop()
	for range t.C {
		t0 := time.Now()
		frame := append([]byte("data: "), token()...)
		frame = append(frame, '\n', '\n')
		n := 0
		mu.Lock()
		for _, s := range streams {
			if s.engID != engID {
				continue
			}
			if writeFrame(s, frame) {
				n++
			}
		}
		mu.Unlock()
		sentTok.Add(uint64(n))
		sentByt.Add(uint64(n) * uint64(len(frame)))
		passTimer(t0)
	}
}

func main() {
	flag.Parse()
	switch *phase {
	case "aligned", "random", "per-engine":
	default:
		panic("bad phase")
	}
	periodD := time.Duration(*period) * time.Millisecond
	const shards = 8
	if *phase == "aligned" {
		// one shared tick, 8 parallel writer goroutines each owning a
		// deterministic stripe of stream IDs (id % shards); a single
		// goroutine cannot write 25k frames inside a 25ms period
		ticks := make([]chan time.Time, shards)
		for sh := range ticks {
			ticks[sh] = make(chan time.Time)
		}
		go func() {
			t := time.NewTicker(periodD)
			for tt := range t.C {
				for _, ch := range ticks {
					ch <- tt
				}
			}
		}()
		for sh := 0; sh < shards; sh++ {
			go func(sh int) {
				for range ticks[sh] {
					t0 := time.Now()
					frame := append([]byte("data: "), token()...)
					frame = append(frame, '\n', '\n')
					// snapshot the stripe under the lock; write outside it
					mu.Lock()
					mine := make([]*stream, 0, len(streams)/shards+1)
					for id, s := range streams {
						if id%shards == sh {
							mine = append(mine, s)
						}
					}
					mu.Unlock()
					n := 0
					for _, s := range mine {
						if writeFrame(s, frame) {
							n++
						}
					}
					sentTok.Add(uint64(n))
					sentByt.Add(uint64(n) * uint64(len(frame)))
					passTimer(t0)
				}
			}(sh)
		}
	}
	http.HandleFunc("/stream", func(w http.ResponseWriter, r *http.Request) {
		fl, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "no flush", 500)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.WriteHeader(200)
		fl.Flush()
		s := &stream{w: w, flush: fl, done: make(chan struct{})}
		mu.Lock()
		if len(streams) >= *nStreams {
			mu.Unlock()
			http.Error(w, "at capacity", 503)
			return
		}
		id := nextID
		nextID++
		s.engID = id / *engSize
		streams[id] = s
		engID := s.engID
		mu.Unlock()
		if *phase == "per-engine" {
			if _, loaded := engOnce.LoadOrStore(engID, true); !loaded {
				go runEngine(engID)
			}
		}
		defer func() {
			mu.Lock()
			delete(streams, id)
			mu.Unlock()
		}()
		if *phase == "random" {
			time.Sleep(time.Duration(rand.Int63n(int64(periodD))))
			t := time.NewTicker(periodD)
			defer t.Stop()
			for {
				select {
				case <-r.Context().Done():
					return
				case <-t.C:
					t0 := time.Now()
					frame := append([]byte("data: "), token()...)
					frame = append(frame, '\n', '\n')
					if !writeFrame(s, frame) {
						return
					}
					sentTok.Add(1)
					sentByt.Add(uint64(len(frame)))
					passTimer(t0)
				}
			}
		}
		<-r.Context().Done()
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		n := len(streams)
		mu.Unlock()
		fmt.Fprintf(w, "streams=%d phase=%s\n", n, *phase)
	})
	http.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		n := len(streams)
		mu.Unlock()
		fmt.Fprintf(w, "streams=%d tokens=%d bytes=%d overruns=%d\n", n, sentTok.Load(), sentByt.Load(), overrun.Load())
	})
	fmt.Fprintf(os.Stderr, "clockemit on %s streams=%d period=%dms phase=%s chunk=%dB\n",
		*listen, *nStreams, *period, *phase, *chunk)
	ln, err := net.Listen("tcp", *listen)
	if err != nil {
		panic(err)
	}
	srv := &http.Server{Handler: nil}
	srv.ConnState = func(c net.Conn, st http.ConnState) {
		if tc, ok := c.(*net.TCPConn); ok && st == http.StateNew {
			tc.SetNoDelay(true)
		}
	}
	if err := srv.Serve(ln); err != nil {
		panic(err)
	}
}
