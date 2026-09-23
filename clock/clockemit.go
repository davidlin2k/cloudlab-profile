// clockemit: step-clock SSE emitter (vLLM-shaped token streaming).
//
// Each stream = one SSE connection. Every step period, each stream
// gets exactly one chunk ("data: <chunk>\n\n"). -phase aligned puts
// every stream on the shared tick (the burst case); -phase random
// gives each stream an independent random offset within the step.
//
// Usage: clockemit -listen :8000 -streams 25000 -period 33 \
//                  -phase aligned -chunk 24
// Endpoints: /stream (SSE), /healthz, /stats
package main

import (
	"flag"
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

var (
	nStreams = flag.Int("streams", 10000, "max concurrent streams")
	period   = flag.Int("period", 33, "step period ms")
	phase    = flag.String("phase", "aligned", "aligned|random")
	chunk    = flag.Int("chunk", 24, "token chunk bytes")
	listen   = flag.String("listen", ":8000", "listen addr")
)

type stream struct {
	w       http.ResponseWriter
	flusher http.Flusher
	done    chan struct{}
	offset  time.Duration
}

var (
	mu      sync.Mutex
	streams = make(map[int]*stream)
	nextID  int
	sentTok atomic.Uint64
	sentByt atomic.Uint64
)

func token() []byte {
	t := make([]byte, *chunk)
	for i := range t {
		t[i] = byte('a' + (i+int(sentTok.Load()))%26)
	}
	return t
}

func emitAll() {
	frame := append([]byte("data: "), token()...)
	frame = append(frame, '\n', '\n')
	n := 0
	mu.Lock()
	for _, s := range streams {
		select {
		case <-s.done:
			continue
		default:
		}
		_, err := s.w.Write(frame)
		if err != nil {
			close(s.done)
			continue
		}
		s.flusher.Flush()
		n++
	}
	mu.Unlock()
	sentTok.Add(uint64(n))
	sentByt.Add(uint64(n) * uint64(len(frame)))
}

func emitOne(s *stream) {
	frame := append([]byte("data: "), token()...)
	frame = append(frame, '\n', '\n')
	select {
	case <-s.done:
		return
	default:
	}
	if _, err := s.w.Write(frame); err != nil {
		close(s.done)
		return
	}
	s.flusher.Flush()
	sentTok.Add(1)
	sentByt.Add(uint64(len(frame)))
}

func main() {
	flag.Parse()
	if *phase == "aligned" {
		go func() {
			t := time.NewTicker(time.Duration(*period) * time.Millisecond)
			for range t.C {
				emitAll()
			}
		}()
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
		s := &stream{w: w, flusher: fl, done: make(chan struct{})}
		if *phase == "random" {
			s.offset = time.Duration(rand.Int63n(int64(*period))) * time.Millisecond
		}
		mu.Lock()
		if len(streams) >= *nStreams {
			mu.Unlock()
			http.Error(w, "at capacity", 503)
			return
		}
		id := nextID
		nextID++
		streams[id] = s
		mu.Unlock()
		defer func() {
			mu.Lock()
			delete(streams, id)
			mu.Unlock()
		}()
		if *phase == "random" {
			off := s.offset
			t := time.NewTicker(time.Duration(*period) * time.Millisecond)
			time.Sleep(off)
			for {
				select {
				case <-r.Context().Done():
					t.Stop()
					return
				case <-t.C:
					emitOne(s)
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
		fmt.Fprintf(w, "streams=%d tokens=%d bytes=%d\n", n, sentTok.Load(), sentByt.Load())
	})
	fmt.Fprintf(os.Stderr, "clockemit on %s streams=%d period=%dms phase=%s chunk=%dB\n",
		*listen, *nStreams, *period, *phase, *chunk)
	if err := http.ListenAndServe(*listen, nil); err != nil {
		panic(err)
	}
}
