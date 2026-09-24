/* k2_rx.c -- pinned UDP consumer for the K2 DDIO-causality measurement.
 *
 * Binds one UDP port and busy-polls it with recvmmsg, touching every
 * payload byte, self-monitored for cycles and cache-misses (like
 * bench/calib.c: perf_event_paranoid=2 permits self-monitoring).
 *
 * K2RX_HIST=1 adds the DMA landing-site measurement: the receive ring
 * cycles over 32k slots (64MB, far beyond any private cache and the
 * 16MB domain L3), so every payload line is fully cold at reuse — its
 * state is whatever the NIC's DMA write left. Per datagram we time
 * (a) the FIRST 8-byte payload word, (b) an immediate re-read of the
 * same word, and (c) a reference line from a known-DRAM array cycled at
 * the same spacing. Bands:
 *   <80 cyc:    L3 resident (DDIO-like allocation)
 *   80-250:     remote-CCD L3 / fabric path
 *   >600:       DRAM resident (non-allocating DMA write path)
 * This distinguishes "AMD has an Intel-DDIO-like mechanism" from "AMD
 * DMA writes go straight to DRAM" — the platform split under the K2
 * floor verdict, and the assumption the Intel-only cache-centric
 * receive literature (rxBisect/Sepia/TiNA) never states.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/perf_event.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include <x86intrin.h>

#ifndef BATCH
#define BATCH 64
#endif
#define BUFLEN 2048
#define NSLOT 32768				/* 64MB recv ring: cold at reuse */

static void die(const char *why)
{
	fprintf(stderr, "k2_rx: %s: %s\n", why, strerror(errno));
	exit(1);
}

static void pin(int cpu)
{
	cpu_set_t s;

	CPU_ZERO(&s);
	CPU_SET(cpu, &s);
	if (sched_setaffinity(0, sizeof(s), &s) < 0)
		die("sched_setaffinity");
}

static int pe_open_cpu(unsigned type, unsigned long long cfg)
{
	struct perf_event_attr a;

	memset(&a, 0, sizeof(a));
	a.type = type;
	a.size = sizeof(a);
	a.config = cfg;
	a.disabled = 0;
	a.exclude_kernel = 1;
	a.exclude_hv = 1;
	return syscall(__NR_perf_event_open, &a, 0, -1, -1, 0);
}

/* Same events but kernel-side included: catches the recvmmsg copy, whose
 * source lines are exactly the DMA write's landing site. */
static int pe_open_all(unsigned type, unsigned long long cfg)
{
	struct perf_event_attr a;

	memset(&a, 0, sizeof(a));
	a.type = type;
	a.size = sizeof(a);
	a.config = cfg;
	a.disabled = 0;
	a.exclude_kernel = 0;
	a.exclude_hv = 0;
	return syscall(__NR_perf_event_open, &a, 0, -1, -1, 0);
}

/* lfence-serialized: required for per-load latency deltas on AMD */
static inline unsigned long long rdtsc_lf(void)
{
	unsigned lo, hi;

	__asm__ __volatile__("lfence; rdtsc" : "=a"(lo), "=d"(hi) :: "memory");
	return ((unsigned long long)hi << 32) | lo;
}

static double now_s(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + 1e-9 * t.tv_nsec;
}

/* this thread's cumulative on-CPU time (ns): frequency-independent
 * app-side cost per packet when differenced across the run */
static unsigned long long schedstat_ns(void)
{
	FILE *f = fopen("/proc/self/schedstat", "r");
	unsigned long long rt = 0;
	if (f) {
		if (fscanf(f, "%llu", &rt) != 1)
			rt = 0;
		fclose(f);
	}
	return rt;
}

int main(int argc, char **argv)
{
	int port = 7777, core = 0, secs = 15, i, j, fd, cyc_fd, miss_fd, one;
	int all = 0, tot_cyc_fd = -1;
	/* p1-LADDER additions: rx-ts->dequeue latency histogram (1us buckets),
	 * socket-drop counter (SO_RXQ_OVFL), 1s window rates on stderr, echo
	 * mode (W2 server), self schedstat (frequency-independent app cost). */
	int echo = 0, refc_fd = -1, skip = 0;
	char dump_arg[256] = "";
	static uint32_t lhist[1 << 20];
	static uint32_t whist[1024];	/* per-1s-window latency p50 (Fig 5) */
	unsigned long long nlat = 0, lat_sum = 0, lat_max = 0;
	unsigned long long sock_drops = 0, echoed = 0, wins = 0, win_pkts = 0;
	uint32_t last_d = 0;
	double win_t0;
	/* AMD Zen4 ls_dmnd_fills_from_sys (event 0x43) by fill source:
	 * exactly the categories the review asks for (L2 hit vs other CCX
	 * cache vs DRAM/IO). raw config = 0x43 | umask << 8 */
	int fill_fd[5] = { -1, -1, -1, -1, -1 };
	static const unsigned fill_umask[5] = { 0x01, 0x02, 0x04, 0x08, 0x10 };
	static const char *const fill_name[5] = { "l2", "ccx", "near", "dram",
						  "fc" };
	(void)fill_name;
	unsigned long long pkts = 0, sum = 0, cyc, miss;
	double t_end;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--port") && i + 1 < argc)
			port = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--core") && i + 1 < argc)
			core = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--secs") && i + 1 < argc)
			secs = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--hist"))
			setenv("K2RX_HIST", "1", 0);
		else if (!strcmp(argv[i], "--echo"))
			echo = 1;
		else if (!strcmp(argv[i], "--skip") && i + 1 < argc)
			skip = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--dump"))
			snprintf(dump_arg, sizeof(dump_arg), "%s", argv[++i]);
		else if (!strcmp(argv[i], "--all"))
			all = 1;	/* also count syscall-side cycles/misses:
					 * for UDP the skb->user copy runs in THIS
					 * thread's recvmmsg, so tot - user exposes
					 * the DMA'd payload's cache state */
		else
			die("usage: k2_rx --port N --core N [--secs 15] [--hist] [--all] [--echo] [--skip W] [--dump F]");
	}
	pin(core);
	cyc_fd = miss_fd = -1;
	if (!all) {
		/* user-only mode: cycles + generic misses */
		cyc_fd = pe_open_cpu(PERF_TYPE_HARDWARE,
				     PERF_COUNT_HW_CPU_CYCLES);
		miss_fd = pe_open_cpu(PERF_TYPE_HARDWARE,
				      PERF_COUNT_HW_CACHE_MISSES);
		refc_fd = pe_open_cpu(PERF_TYPE_HARDWARE,
				      PERF_COUNT_HW_REF_CPU_CYCLES);
		if (cyc_fd < 0 || miss_fd < 0)
			die("perf_event_open (paranoid level?)");
	} else {
		/* --all mode: 1 cycles counter (exclude_kernel=0) +
		 * 5 fill-source events = exactly the 6 Zen4 PMCs.
		 * The user-only pair cannot coexist (would multiplex). */
		tot_cyc_fd = pe_open_all(PERF_TYPE_HARDWARE,
					 PERF_COUNT_HW_CPU_CYCLES);
		for (i = 0; i < 5; i++)
			fill_fd[i] = pe_open_all(PERF_TYPE_RAW,
						 (unsigned long long)0x43 |
						 ((unsigned long long)
						  fill_umask[i] << 8));
		if (tot_cyc_fd < 0 || fill_fd[0] < 0 || fill_fd[1] < 0 ||
		    fill_fd[2] < 0 || fill_fd[3] < 0 || fill_fd[4] < 0)
			die("perf_event_open (fill sources)");
	}

	fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0)
		die("socket");
	one = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
	int buf = 64 << 20;
	setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buf, sizeof(buf));
	setsockopt(fd, SOL_SOCKET, SO_TIMESTAMPNS, &one, sizeof(one));
	setsockopt(fd, SOL_SOCKET, SO_RXQ_OVFL, &one, sizeof(one));
	/* don't block forever: the loop must re-check its deadline */
	{
		struct timeval tv = { .tv_sec = 0, .tv_usec = 200000 };
		setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	}
	struct sockaddr_in a;
	memset(&a, 0, sizeof(a));
	a.sin_family = AF_INET;
	a.sin_port = htons(port);
	if (bind(fd, (struct sockaddr *)&a, sizeof(a)) < 0)
		die("bind");

	int inc_cpu = -1;
	socklen_t sl = sizeof(inc_cpu);
	getsockopt(fd, SOL_SOCKET, SO_INCOMING_CPU, &inc_cpu, &sl);

	static char bufs[BATCH][BUFLEN] __attribute__((aligned(64)));
	struct mmsghdr mm[BATCH];
	struct iovec iov[BATCH];
	static char ctl[BATCH][256];
	static struct sockaddr_storage src[BATCH];
	memset(mm, 0, sizeof(mm));	/* msg_name/msg_control must be zero:
					 * garbage makes recvmmsg EFAULT */
	for (i = 0; i < BATCH; i++) {
		iov[i].iov_base = bufs[i];
		iov[i].iov_len = BUFLEN;
		mm[i].msg_hdr.msg_iov = &iov[i];
		mm[i].msg_hdr.msg_iovlen = 1;
		mm[i].msg_hdr.msg_name = &src[i];
		mm[i].msg_hdr.msg_namelen = sizeof(src[i]);
		mm[i].msg_hdr.msg_control = ctl[i];
		mm[i].msg_hdr.msg_controllen = sizeof(ctl[i]);
	}

	char (*big)[BUFLEN] = NULL;
	unsigned long long *ref = NULL;
	if (getenv("K2RX_HIST")) {
		big = mmap(NULL, (size_t)NSLOT * BUFLEN, PROT_READ | PROT_WRITE,
			   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (big == MAP_FAILED)
			die("mmap big");
		ref = mmap(NULL, 16 << 20, PROT_READ | PROT_WRITE,
			   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (ref == MAP_FAILED)
			die("mmap ref");
		memset(ref, 0x5a, 16 << 20);
	}
	unsigned long long h1 = 0, h2 = 0, h3 = 0, h4 = 0;	/* first touch */
	unsigned long long r1 = 0, r2 = 0, r3 = 0, r4 = 0;	/* reference */
	unsigned long long ft_sum = 0, rft_sum = 0, st_sum = 0;
	long slot = 0;
	unsigned long long refpos = 0;

	unsigned long long app_ns0 = schedstat_ns();
	t_end = now_s() + secs;
	win_t0 = now_s();
	double t_meas = win_t0 + skip;
	int meas = !skip;
	unsigned long long mpkts = 0, bytes = 0;
	while (now_s() < t_end) {
		for (i = 0; i < BATCH; i++) {
			mm[i].msg_hdr.msg_controllen = sizeof(ctl[i]);
			mm[i].msg_hdr.msg_namelen = sizeof(src[i]);
		}
		int n = recvmmsg(fd, mm, BATCH, MSG_WAITFORONE, NULL);
		if (n < 0)
			continue;
		struct timespec dr;
		clock_gettime(CLOCK_REALTIME, &dr);
		if (!meas && now_s() >= t_meas)
			meas = 1;
		for (i = 0; i < n; i++) {
			int len = mm[i].msg_len;
			bytes += len;
			struct timespec rxts;
			uint32_t d = 0;
			int have_ovfl = 0;
			memset(&rxts, 0, sizeof(rxts));
			for (struct cmsghdr *cm = CMSG_FIRSTHDR(&mm[i].msg_hdr);
			     cm; cm = CMSG_NXTHDR(&mm[i].msg_hdr, cm)) {
				if (cm->cmsg_level == SOL_SOCKET &&
				    cm->cmsg_type == SCM_TIMESTAMPNS)
					memcpy(&rxts, CMSG_DATA(cm),
					       sizeof(rxts));
				if (cm->cmsg_level == SOL_SOCKET &&
				    cm->cmsg_type == SO_RXQ_OVFL) {
					memcpy(&d, CMSG_DATA(cm), sizeof(d));
					have_ovfl = 1;
				}
			}
			if (have_ovfl) {
				sock_drops += d - last_d;
				last_d = d;
			}
			if (meas && (rxts.tv_sec || rxts.tv_nsec)) {
				int64_t ns = (int64_t)(dr.tv_sec -
						       rxts.tv_sec) *
					     1000000000LL + dr.tv_nsec -
					     rxts.tv_nsec;
				uint64_t l = ns < 0 ? 0 : (uint64_t)ns;
				lat_sum += l; nlat++;
				if (l > lat_max) lat_max = l;
				unsigned b = l / 1000;
				lhist[b < (1u << 20) ? b : (1u << 20) - 1]++;
				whist[b < 1024 ? b : 1023]++;
			}
			if (echo && mm[i].msg_hdr.msg_namelen)
				echoed += sendto(fd, bufs[i], len, 0,
						 (struct sockaddr *)&src[i],
						 mm[i].msg_hdr.msg_namelen) > 0;
			unsigned long long *w;
			if (big) {
				w = (unsigned long long *)
					big[slot & (NSLOT - 1)];
				slot += 1 + len / BUFLEN;
				if (len > BUFLEN)
					len = BUFLEN;
			} else {
				w = (unsigned long long *)bufs[i];
			}
			unsigned long long t0 = rdtsc_lf();
			volatile unsigned long long v0 = w[0];	/* first touch */
			unsigned long long t1 = rdtsc_lf();
			volatile unsigned long long v1 = w[0];	/* second touch */
			unsigned long long t1s = rdtsc_lf();
			unsigned long long ft = t1 - t0, st = t1s - t1;
			for (j = 8; j + 8 <= len; j += 8)
				sum += w[j / 8];
			(void)v0;
			(void)v1;
			ft_sum += ft;
			st_sum += st;
			if (ft < 80) h1++;
			else if (ft < 250) h2++;
			else if (ft < 600) h3++;
			else h4++;
			if (ref) {	/* reference DRAM line, same spacing */
				unsigned long long t3 = rdtsc_lf();
				volatile unsigned long long v2 = ref[refpos];
				unsigned long long t4 = rdtsc_lf();
				volatile unsigned long long v3 = ref[refpos];
				unsigned long long rt = t4 - t3;
				(void)v2;
				(void)v3;
				rft_sum += rt;
				if (rt < 80) r1++;
				else if (rt < 250) r2++;
				else if (rt < 600) r3++;
				else r4++;
				refpos += 2048;	/* 16MB stride: fully cold */
				if (refpos >= (16 << 20) / sizeof(*ref))
					refpos = 0;
			}
			pkts++;
			win_pkts++;
			if (meas)
				mpkts++;
		}
		double nw = now_s();
		if (nw - win_t0 >= 1.0) {
			{
				unsigned long long totw = 0, accw = 0, wp50 = 0;
				for (unsigned b2 = 0; b2 < 1024; b2++)
					totw += whist[b2];
				for (unsigned b2 = 0; b2 < 1024; b2++) {
					accw += whist[b2];
					if (!wp50 && accw * 2 >= totw)
						wp50 = b2;
				}
				fprintf(stderr,
					"[k2rx-win] t=%.0f pkts=%llu rate=%.0f drops=%llu wp50_us=%llu\n",
					nw - (t_end - secs), win_pkts,
					win_pkts / (nw - win_t0), sock_drops,
					totw ? wp50 : 0);
				memset(whist, 0, sizeof(whist));
			}
			wins++;
			win_pkts = 0;
			win_t0 = nw;
		}
	}
	unsigned long long app_ns = schedstat_ns() - app_ns0;
	uint64_t v;
	cyc = miss = 0;
	if (cyc_fd >= 0) {
		if (read(cyc_fd, &v, 8) == 8)
			cyc = v;
		{ int ov = 0; socklen_t ol = sizeof(ov);
		  getsockopt(fd, SOL_SOCKET, SO_RXQ_OVFL, &ov, &ol);
		  if ((unsigned)ov > sock_drops) sock_drops = ov; }
		if (read(miss_fd, &v, 8) == 8)
			miss = v;
		printf("k2rx port=%d core=%d incpu=%d pkts=%llu sum=%llu "
		       "cyc/pkt=%.1f miss/pkt=%.2f",
		       port, core, inc_cpu, pkts, bytes,
		       pkts ? (double)cyc / pkts : -1.0,
		       pkts ? (double)miss / pkts : -1.0);
	} else {
		printf("k2rx port=%d core=%d incpu=%d pkts=%llu sum=%llu "
		       "cyc/pkt=%.1f",
		       port, core, inc_cpu, pkts, bytes,
		       pkts ? (double)cyc / pkts : -1.0);
	}
	{
		double p50 = -1, p90 = -1, p99 = -1, p999 = -1;
		unsigned long long acc = 0, b;
		for (b = 0; b < (1u << 20); b++) {
			acc += lhist[b];
			double us = (double)b + 0.5;
			if (p50 < 0 && acc >= 50 * nlat / 100) p50 = us;
			if (p90 < 0 && acc >= 90 * nlat / 100) p90 = us;
			if (p99 < 0 && acc >= 99 * nlat / 100) p99 = us;
			if (p999 < 0 && acc >= 999 * nlat / 1000) p999 = us;
		}
		double refc = -1;
		if (refc_fd >= 0) {
			uint64_t rv = 0;
			if (read(refc_fd, &rv, 8) == 8)
				refc = pkts ? (double)rv / pkts : -1.0;
		}
		printf(" | lat mean_us=%.1f p50_us=%.1f p90_us=%.1f p99_us=%.1f "
		       "p99.9_us=%.1f max_us=%.1f sockdrops=%llu echoed=%llu "
		       "wins=%llu mpkts=%llu app_ns/pkt=%.1f refcyc/pkt=%.1f",
		       nlat ? (double)lat_sum / nlat / 1000.0 : -1.0,
		       p50, p90, p99, p999, lat_max / 1000.0,
		       sock_drops, echoed, wins, mpkts,
		       pkts ? (double)app_ns / pkts : -1.0, refc);
		if (p50 >= 0 && p50 < 1.0 && nlat > 100)
			fprintf(stderr,
				"GATEWARN k2_rx: sw rx->dequeue p50 %.2fus "
				"< 1us - timestamp phase bug suspected\n", p50);
	}
	if (big)
		printf(" | FT <80:%llu 80-250:%llu 250-600:%llu >=600:%llu "
		       "ftavg=%.0f stavg=%.0f | REF <80:%llu 80-250:%llu "
		       "250-600:%llu >=600:%llu refavg=%.0f",
		       h1, h2, h3, h4,
		       pkts ? (double)ft_sum / pkts : -1.0,
		       pkts ? (double)st_sum / pkts : -1.0,
		       r1, r2, r3, r4,
		       pkts ? (double)rft_sum / pkts : -1.0);
	if (tot_cyc_fd >= 0) {
		uint64_t tc = 0;
		double fr[5] = { 0, 0, 0, 0, 0 };
		int k;
		uint64_t fv;
		if (read(tot_cyc_fd, &v, 8) == 8)
			tc = v;
		for (k = 0; k < 5; k++) {
			fv = 0;
			if (read(fill_fd[k], &fv, 8) == 8)
				fr[k] = pkts ? (double)fv / pkts : -1.0;
		}
		printf(" | tot cyc/pkt=%.1f fills/pkt l2=%.2f ccx=%.2f "
		       "near=%.2f dram=%.2f fcache=%.2f",
		       pkts ? (double)tc / pkts : -1.0,
		       fr[0], fr[1], fr[2], fr[3], fr[4]);
	}
	if (dump_arg[0]) {
		FILE *df = fopen(dump_arg, "w");
		if (df) {
			for (unsigned long long b = 0; b < (1ull << 20); b++)
				if (lhist[b]) fprintf(df, "%llu %u\n", b, lhist[b]);
			fclose(df);
		} else {
			fprintf(stderr, "k2_rx: cannot write %s\n", dump_arg);
		}
	}
	printf("\n");
	return 0;
}