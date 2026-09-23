/* k4send.c -- Reins seed client v2: hint-following RPC sender. ONE
 * socket bound to the sender's OWN IP; each RPC is sent to a dport
 * authored (via the known RSS key) to land on a chosen queue. The
 * receiver's echo carries a hint byte at [n-1] = the queue INDEX
 * (index into the receiver's core pool); the sender maps index ->
 * dport via --qmap and follows. Requests carry an 8-byte monotonic tx
 * timestamp in bytes [n-10..n-3]. Experiment network only.
 *
 * Build: gcc -Wall -O2 -o k4send k4send.c -lpthread
 * Usage: sudo ./k4send --dip 10.10.1.1 --sip 10 --qmap 0:7777,1:7804 \
 *          --n 80000 --plen 300 --depth 64 --rate 120000 --follow 1 --core 2
 *   --qmap  idx:port[,...]  index->dport map (indexes align with the
 *                           receiver's --ports order)
 *   --follow 0 ignores hints (the static-RSS control). */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define PL 1600
#define HIST (1 << 20)
#define SCALE 1000.0			/* 1us per bucket; range ~1.05s */
#define RTT_FLOOR_US 10.0		/* abort if p50 below: units bug canary */
#define MAXQ 8

static void die(const char *m) { perror(m); exit(1); }
static uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}
static void put64(char *p, uint64_t v)
{
	for (int i = 0; i < 8; i++) p[i] = (char)((v >> (8 * i)) & 0xff);
}
static uint64_t get64(const char *p)
{
	uint64_t v = 0;
	for (int i = 7; i >= 0; i--) v = (v << 8) | (uint8_t)p[i];
	return v;
}

int main(int argc, char **argv)
{
	int n = 80000, plen = 300, depth = 64, follow = 1, core = -1;
	int start_qidx = 0;
	int burst = 1, lport = 0;
	long rate = 120000;
	char dip[64] = "10.10.1.1", qmap_arg[256] = "";
	int sip_octet = 0;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--dip")) snprintf(dip, sizeof(dip), "%s", argv[++i]);
		else if (!strcmp(argv[i], "--sip")) sip_octet = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--qmap")) snprintf(qmap_arg, sizeof(qmap_arg), "%s", argv[++i]);
		else if (!strcmp(argv[i], "--n")) n = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--plen")) plen = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--depth")) depth = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--burst")) burst = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--lport")) lport = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--rate")) rate = atol(argv[++i]);
		else if (!strcmp(argv[i], "--follow")) follow = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--start")) start_qidx = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--core")) core = atoi(argv[++i]);
		else { fprintf(stderr, "k4send: unknown arg %s\n", argv[i]); return 1; }
	}
	if (!qmap_arg[0] || !sip_octet) {
		fprintf(stderr, "usage: k4send --sip OCTET --qmap 0:7777,1:7804 --n N --depth D --rate R --follow F --core C\n");
		return 1;
	}
	int port_for[MAXQ];
	for (int i = 0; i < MAXQ; i++) port_for[i] = -1;
	int nq = 0;
	char *save = NULL;
	for (char *tok = strtok_r(qmap_arg, ",", &save); tok && nq < MAXQ;
	     tok = strtok_r(NULL, ",", &save)) {
		char *colon = strchr(tok, ':');
		if (!colon) { fprintf(stderr, "bad qmap entry %s\n", tok); return 1; }
		int idx = atoi(tok), dp = atoi(colon + 1);
		if (idx < 0 || idx >= MAXQ) { fprintf(stderr, "bad qmap idx\n"); return 1; }
		port_for[idx] = dp;
		nq++;
	}
	int cur = start_qidx;		/* current pool index */
	if (!port_for[cur]) { fprintf(stderr, "qmap must define index %d\n", cur); return 1; }
	if (core >= 0) {
		cpu_set_t cs;
		CPU_ZERO(&cs); CPU_SET(core, &cs);
		sched_setaffinity(0, sizeof(cs), &cs);
	}
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	int sz = 8 << 20;
	setsockopt(fd, SOL_SOCKET, SO_SNDBUFFORCE, &sz, sizeof(sz));
	setsockopt(fd, SOL_SOCKET, SO_RCVBUFFORCE, &sz, sizeof(sz));
	struct timeval tv = { .tv_sec = 0, .tv_usec = 50000 };
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	if (sip_octet) {
		char ip[32];
		snprintf(ip, sizeof(ip), "10.10.1.%d", sip_octet);
		struct sockaddr_in s;
		memset(&s, 0, sizeof(s));
		s.sin_family = AF_INET;
		inet_pton(AF_INET, ip, &s.sin_addr);
		if (lport) s.sin_port = htons(lport);
		if (bind(fd, (struct sockaddr *)&s, sizeof(s)) < 0) die("bind sip");
	}
	struct sockaddr_in da;
	memset(&da, 0, sizeof(da));
	da.sin_family = AF_INET;
	inet_pton(AF_INET, dip, &da.sin_addr);

	static char req[PL];
	for (int i = 0; i < plen; i++) req[i] = (char)(i & 0xff);

	int hist[HIST] = {0};
	uint64_t responses = 0, switches = 0;
	uint64_t nlow = 0, nshort = 0;
	double min_lat = -1;
	uint64_t quuse[MAXQ] = {0};
	uint64_t t0 = now_ns(), t_next = now_ns(), t_end = t0 + 120000000000ull;
	uint64_t gap = (uint64_t)(1e9 / (double)rate);
	uint64_t sent = 0;
	uint64_t last_switch = 0;

	/* open-loop send on a timer; echoes are drained CONTINUOUSLY
	 * (between ticks too) so the measured RTT excludes the sender's
	 * own inter-send idle time */
	while (sent < (uint64_t)n && now_ns() < t_end) {
		/* drain any pending echoes (non-blocking) */
		for (;;) {
			char rbuf[PL];
			struct sockaddr_in from;
			socklen_t fl = sizeof(from);
			int rn = recvfrom(fd, rbuf, sizeof(rbuf), MSG_DONTWAIT,
					  (struct sockaddr *)&from, &fl);
			if (rn < 0) break;
			responses++;
			if (rn != plen) { nshort++; continue; }
			uint64_t tx = get64(rbuf + rn - 10);
			double lat = (double)(now_ns() - tx);
			if (min_lat < 0 || lat < min_lat) min_lat = lat;
			if (lat < RTT_FLOOR_US * 1000.0) {
				nlow++;
				if (responses > 1000 && nlow * 100 >
				    (uint64_t)responses) {
					fprintf(stderr, "[k4send] GATE FAIL: "
						"RTTs below %.0fus floor "
						"(%llu/%llu) - units/histogram "
						"bug, discard run\n",
						RTT_FLOOR_US,
						(unsigned long long)nlow,
						(unsigned long long)responses);
					exit(2);
				}
			}
			int idx = (int)(lat / SCALE);
			if (idx >= HIST) idx = HIST - 1;
			if (idx < 0) idx = 0;
			hist[idx]++;
			if (rn >= 1) {
				int hq = (uint8_t)rbuf[rn - 1];
				if (follow && hq != cur && hq >= 0 && hq < MAXQ &&
				    port_for[hq] > 0 &&
				    now_ns() - last_switch > 100000000ull) {
					cur = hq;
					switches++;
					last_switch = now_ns();
				}
			}
		}
		uint64_t tn = now_ns();
		if (tn < t_next) continue;	/* busy-poll to the tick */
		t_next += gap;
		if (t_next < tn) t_next = tn + gap;
		put64(req + plen - 10, now_ns());
		da.sin_port = htons(port_for[cur]);
		if (sendto(fd, req, plen, 0, (struct sockaddr *)&da, sizeof(da)) < 0)
			die("sendto");
		quuse[cur]++; sent++;
	}
	/* drain trailing echoes for up to 10s after the send window */
	uint64_t drain_end = now_ns() + 10000000000ull;
	while (responses < sent && now_ns() < drain_end) {
		char rbuf[PL];
		struct sockaddr_in from;
		socklen_t fl = sizeof(from);
		int rn = recvfrom(fd, rbuf, sizeof(rbuf), MSG_DONTWAIT,
				  (struct sockaddr *)&from, &fl);
		if (rn >= 0) {
			responses++;
			if (rn != plen) { nshort++; continue; }
			uint64_t tx = get64(rbuf + rn - 10);
			double lat = (double)(now_ns() - tx);
			if (min_lat < 0 || lat < min_lat) min_lat = lat;
			if (lat < RTT_FLOOR_US * 1000.0) nlow++;
			int idx = (int)(lat / SCALE);
			if (idx >= HIST) idx = HIST - 1;
			if (idx < 0) idx = 0;
			hist[idx]++;
		} else {
			struct timespec ts = { 0, 1000000 };
			nanosleep(&ts, NULL);
		}
	}
	double wall = (now_ns() - t0) / 1e9;
	uint64_t cum = 0;
	double pcts[4] = { 50, 90, 99, 99.9 };
	double outp[4] = { 0, 0, 0, 0 };
	int pi = 0;
	for (int i = 0; i < HIST && pi < 4; i++) {
		cum += hist[i];
		while (pi < 4 && (double)cum >= (double)responses * pcts[pi] / 100.0)
			outp[pi++] = (i + 1) * SCALE / 1000.0;
	}
	uint64_t sum = 0;
	for (int i = 0; i < HIST; i++)
		sum += (uint64_t)((i + 0.5) * SCALE) * hist[i];
	double mean = responses ? (double)sum / responses / 1000.0 : 0;
	printf("[k4send] sip=10.10.1.%d n=%d sent=%llu resp=%llu censored=%llu switches=%llu "
	       "wall=%.1fs rate=%.0f/s mean=%.1fus p50=%.1f p90=%.1f p99=%.1f p99.9=%.1f "
	       "min=%.1fus nlow=%llu nshort=%llu\n",
	       sip_octet, n, (unsigned long long)sent,
	       (unsigned long long)responses,
	       (unsigned long long)(sent - responses),
	       (unsigned long long)switches, wall,
	       responses / wall, mean,
	       outp[0], outp[1], outp[2], outp[3],
	       min_lat < 0 ? -1.0 : min_lat / 1000.0,
	       (unsigned long long)nlow, (unsigned long long)nshort);
	for (int i = 0; i < MAXQ; i++)
		if (quuse[i])
			printf("[k4send]   qidx=%d dport=%d rpcs=%llu\n",
			       i, port_for[i], (unsigned long long)quuse[i]);
	/* run gates: any violation discards the run (exit != 0) */
	if (responses > sent) {
		fprintf(stderr, "[k4send] GATE FAIL: resp=%llu > sent=%llu "
			"(stale echoes from another run?)\n",
			(unsigned long long)responses,
			(unsigned long long)sent);
		return 2;
	}
	if (nshort) {
		fprintf(stderr, "[k4send] GATE FAIL: %llu echoes with "
			"len != plen (corrupt/short echo)\n",
			(unsigned long long)nshort);
		return 2;
	}
	uint64_t qsum = 0;
	for (int i = 0; i < MAXQ; i++) qsum += quuse[i];
	if (qsum != sent) {
		fprintf(stderr, "[k4send] GATE FAIL: per-port sent %llu != "
			"total sent %llu\n", (unsigned long long)qsum,
			(unsigned long long)sent);
		return 2;
	}
	if (responses > 100 && outp[0] < RTT_FLOOR_US) {
		fprintf(stderr, "[k4send] GATE FAIL: p50 RTT %.1fus < %.0fus "
			"floor (units/phase bug, cf. K4PART 300ns)\n",
			outp[0], RTT_FLOOR_US);
		return 2;
	}
	if (min_lat > 0 && min_lat < 2000.0) {
		fprintf(stderr, "[k4send] GATE FAIL: min RTT %.0fns < 2us "
			"(physically impossible)\n", min_lat);
		return 2;
	}
	return 0;
}