// clocksink: reads N SSE streams through the proxy and measures
// delivery: tokens/s, p50/p99 inter-token latency, stalls (>1s gaps),
// and errors. Shards dials across nports proxy listen ports.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"net/http"
	neturl "net/url"
	"os"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

var (
	proxy   = flag.String("proxy", "http://10.10.1.1:9000", "proxy base URL")
	nS      = flag.Int("streams", 10000, "streams this sink opens")
	listen  = flag.String("listen", ":9200", "stats listen addr")
	rateWin = flag.Int("window", 2, "rate window seconds")
	dialR   = flag.Int("dial-rate", 10000, "dials per second")
	nPorts  = flag.Int("nports", 4, "proxy listen ports to shard across (9000..)")
)

var (
	okToks atomic.Uint64
	errs   atomic.Uint64
	live   atomic.Int64
	lastT  atomic.Int64 // unix ms of last window sample
	lastC  atomic.Uint64
	stalls  atomic.Uint64
	stallMs atomic.Uint64 // total gap ms when dt > 1s
	latMu  sync.Mutex
	latMs  []int64 // inter-token latency samples (capped)
)

const maxSamples = 400000

func recordLat(dt int64) {
	if dt > 1000 {
		stalls.Add(1)
		stallMs.Add(uint64(dt))
	}
	latMu.Lock()
	if len(latMs) < maxSamples {
		latMs = append(latMs, dt)
	}
	latMu.Unlock()
}

var limiter = make(chan struct{}, 1)

func runOne(id int, wg *sync.WaitGroup) {
	defer wg.Done()
	limiter <- struct{}{}
	time.Sleep(time.Second / time.Duration(*dialR))
	<-limiter
	// endpoints: -proxy is either "host" (shard across nPorts listen
	// ports 9000+) or a comma-separated "host:port,host:port,..." list
	// (bypass test: point straight at the emitters)
	var url string
	if strings.Contains(*proxy, ",") {
		eps := strings.Split(*proxy, ",")
		url = fmt.Sprintf("http://%s/stream?s=%d", eps[id%len(eps)], id)
	} else {
		u, _ := neturl.Parse(*proxy)
		host := u.Hostname()
		if host == "" {
			host = "127.0.0.1"
		}
		url = fmt.Sprintf("http://%s:%d/stream?s=%d", host, 9000+id%*nPorts, id)
	}
	req, _ := http.NewRequest("GET", url, nil)
	tr := &http.Transport{
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
	var last int64 = -1
	for {
		_, err := br.ReadBytes('\n') // "data: ..."
		if err != nil {
			errs.Add(1)
			return
		}
		_, err = br.ReadBytes('\n') // blank
		if err != nil {
			errs.Add(1)
			return
		}
		now := time.Now().UnixMilli()
		if last >= 0 {
			recordLat(now - last)
		}
		last = now
		okToks.Add(1)
	}
}

func percentile(sorted []int64, p float64) int64 {
	if len(sorted) == 0 {
		return 0
	}
	return sorted[int(float64(len(sorted)-1)*p)]
}

func statsLine() string {
	latMu.Lock()
	cp := make([]int64, len(latMs))
	copy(cp, latMs)
	latMu.Unlock()
	sort.Slice(cp, func(i, j int) bool { return cp[i] < cp[j] })
	p50 := percentile(cp, 0.5)
	p99 := percentile(cp, 0.99)
	return fmt.Sprintf("live=%d tokens=%d errs=%d stalls=%d stall_s=%.0f p50_itl_ms=%d p99_itl_ms=%d",
		live.Load(), okToks.Load(), errs.Load(), stalls.Load(), float64(stallMs.Load())/1000, p50, p99)
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
				fmt.Fprintf(os.Stderr, "rate=%.0f tok/s %s\n", rate, statsLine())
			}
			lastT.Store(now)
			lastC.Store(c)
		}
	}()
	http.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, statsLine()+"\n")
	})
	go http.ListenAndServe(*listen, nil)
	wg.Wait()
}
