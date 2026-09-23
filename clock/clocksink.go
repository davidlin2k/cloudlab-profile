// clocksink: reads N SSE streams through a proxy and counts delivery.
//
// Usage: clocksink -proxy http://10.10.1.1:9000 -streams 50000 \
//                  -sink-base 0   // this shard's stream-id offset
// Reports delivered tokens/s, read errors, stalls. /stats endpoint.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

var (
	proxy   = flag.String("proxy", "http://10.10.1.1:9000", "proxy base URL")
	nS      = flag.Int("streams", 10000, "streams this sink opens")
	listen  = flag.String("listen", ":9200", "stats listen addr")
	dialTO  = flag.Duration("dial-timeout", 30*time.Second, "dial timeout")
	rateWin = flag.Int("window", 2, "rate window seconds")
	dialR   = flag.Int("dial-rate", 4000, "dials per second")
)

var limiter = make(chan struct{}, 1)

func allow() {
	limiter <- struct{}{}
	time.Sleep(time.Second / time.Duration(*dialR))
	<-limiter
}

var (
	okToks atomic.Uint64
	errs   atomic.Uint64
	live   atomic.Int64
	lastT  atomic.Int64 // unix ms of last window sample
	lastC  atomic.Uint64
)

func runOne(id int, wg *sync.WaitGroup) {
	defer wg.Done()
	allow()
	url := fmt.Sprintf("%s/stream?s=%d", *proxy, id)
	req, _ := http.NewRequest("GET", url, nil)
	tr := &http.Transport{
		MaxIdleConns:        0,
		MaxConnsPerHost:     0,
		IdleConnTimeout:     0,
		DisableKeepAlives:   false,
		MaxIdleConnsPerHost: 1,
	}
	cl := &http.Client{Transport: tr, Timeout: 0}
	resp, err := cl.Do(req)
	if err != nil {
		errs.Add(1)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		errs.Add(1)
		return
	}
	live.Add(1)
	defer live.Add(-1)
	br := bufio.NewReaderSize(resp.Body, 4096)
	for {
		_, err := br.ReadBytes('\n')
		if err != nil {
			errs.Add(1)
			return
		}
		// two lines per token frame: "data: ..." + blank
		_, err = br.ReadBytes('\n')
		if err != nil {
			errs.Add(1)
			return
		}
		okToks.Add(1)
	}
}

func main() {
	flag.Parse()
	var wg sync.WaitGroup
	for i := 0; i < *nS; i++ {
		wg.Add(1)
		go runOne(i, &wg)
	}
	go func() {
		for {
			time.Sleep(time.Duration(*rateWin) * time.Second)
			now := time.Now().UnixMilli()
			c := okToks.Load()
			pn := lastT.Load()
			pc := lastC.Load()
			if pn > 0 {
				rate := float64(c-pc) / (float64(now-pn) / 1000.0)
				fmt.Fprintf(os.Stderr, "rate=%.0f tok/s live=%d errs=%d total=%d\n",
					rate, live.Load(), errs.Load(), c)
			}
			lastT.Store(now)
			lastC.Store(c)
		}
	}()
	http.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "live=%d tokens=%d errs=%d\n", live.Load(), okToks.Load(), errs.Load())
	})
	go http.ListenAndServe(*listen, nil)
	wg.Wait()
}
