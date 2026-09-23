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

int main(int argc, char **argv)
{
	int port = 7777, core = 0, secs = 15, i, j, fd, cyc_fd, miss_fd, one;
	int all = 0, tot_cyc_fd = -1;
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
		else if (!strcmp(argv[i], "--all"))
			all = 1;	/* also count syscall-side cycles/misses:
					 * for UDP the skb->user copy runs in THIS
					 * thread's recvmmsg, so tot - user exposes
					 * the DMA'd payload's cache state */
		else
			die("usage: k2_rx --port N --core N [--secs 15] [--hist] [--all]");
	}
	pin(core);
	cyc_fd = miss_fd = -1;
	if (!all) {
		/* user-only mode: cycles + generic misses */
		cyc_fd = pe_open_cpu(PERF_TYPE_HARDWARE,
				     PERF_COUNT_HW_CPU_CYCLES);
		miss_fd = pe_open_cpu(PERF_TYPE_HARDWARE,
				      PERF_COUNT_HW_CACHE_MISSES);
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
	memset(mm, 0, sizeof(mm));	/* msg_name/msg_control must be zero:
					 * garbage makes recvmmsg EFAULT */
	for (i = 0; i < BATCH; i++) {
		iov[i].iov_base = bufs[i];
		iov[i].iov_len = BUFLEN;
		mm[i].msg_hdr.msg_iov = &iov[i];
		mm[i].msg_hdr.msg_iovlen = 1;
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

	t_end = now_s() + secs;
	while (now_s() < t_end) {
		int n = recvmmsg(fd, mm, BATCH, MSG_WAITFORONE, NULL);
		if (n < 0)
			continue;
		for (i = 0; i < n; i++) {
			int len = mm[i].msg_len;
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
		}
	}
	uint64_t v;
	cyc = miss = 0;
	if (cyc_fd >= 0) {
		if (read(cyc_fd, &v, 8) == 8)
			cyc = v;
		if (read(miss_fd, &v, 8) == 8)
			miss = v;
		printf("k2rx port=%d core=%d incpu=%d pkts=%llu sum=%llu "
		       "cyc/pkt=%.1f miss/pkt=%.2f",
		       port, core, inc_cpu, pkts, sum,
		       pkts ? (double)cyc / pkts : -1.0,
		       pkts ? (double)miss / pkts : -1.0);
	} else {
		printf("k2rx port=%d core=%d incpu=%d pkts=%llu sum=%llu "
		       "cyc/pkt=%.1f",
		       port, core, inc_cpu, pkts, sum,
		       pkts ? (double)cyc / pkts : -1.0);
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
	printf("\n");
	return 0;
}