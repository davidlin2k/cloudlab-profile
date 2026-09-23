/* k3mot.c -- motivating breakdown: short-RPC latency from kernel rx
 * timestamp to application dequeue under bursty fan-in, on default Linux.
 * Measures per-packet (dequeue - rx_ts) via SO_TIMESTAMPNS + recvmsg,
 * counts socket drops via SO_RXQ_OVFL, reports percentiles.
 * The premise test: does the NIC->application segment own the tail?
 * Experiment network only. */
#define _GNU_SOURCE
#include <errno.h>
#include <linux/net_tstamp.h>
#include <netinet/in.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define HIST_US (1 << 20)		/* 1us buckets: 0..~1.05s */
#define BUFLEN 2048

static void die(const char *m) { perror(m); exit(1); }

static void pin(int c)
{
	cpu_set_t s;
	CPU_ZERO(&s);
	CPU_SET(c, &s);
	if (sched_setaffinity(0, sizeof(s), &s) < 0) die("sched_setaffinity");
}

int main(int argc, char **argv)
{
	int port = 7777, core = 0, secs = 20, i;
	int hwt = 0;
	struct sockaddr_in ad;
	uint64_t pkts = 0, drops = 0, sum_d = 0;
	static uint32_t hist[HIST_US];
	double t_end;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--port") && i + 1 < argc)
			port = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--core") && i + 1 < argc)
			core = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--secs") && i + 1 < argc)
			secs = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--hwtstamp"))
			hwt = 1;
		else { fprintf(stderr, "usage: k3mot --port N --core N --secs N "
				       "[--hwtstamp]\n"); exit(1); }
	}
	pin(core);

	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0) die("socket");
	int one = 1, sz = 64 << 20;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, 4);
	setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &sz, sizeof(sz));
	setsockopt(fd, SOL_SOCKET, SO_TIMESTAMPNS, &one, 4);
	if (hwt) {
		/* hardware RX timestamps (NIC PHC) alongside the software
		 * (stack-entry) stamp: the (sw - hw) gap is the NIC-ring
		 * wait + softirq dispatch, accurate to the ptp4l/phc2sys
		 * sync error */
		int tsing = SOF_TIMESTAMPING_RX_SOFTWARE |
			    SOF_TIMESTAMPING_RX_HARDWARE |
			    SOF_TIMESTAMPING_RAW_HARDWARE;
		if (setsockopt(fd, SOL_SOCKET, SO_TIMESTAMPING, &tsing,
			       sizeof(tsing)) < 0)
			die("SO_TIMESTAMPING");
	}
	setsockopt(fd, SOL_SOCKET, SO_RXQ_OVFL, &one, 4);
	/* don't block forever: the loop must re-check its deadline */
	struct timeval tv = { .tv_sec = 0, .tv_usec = 200000 };
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	memset(&ad, 0, sizeof(ad));
	ad.sin_family = AF_INET;
	ad.sin_addr.s_addr = INADDR_ANY;
	ad.sin_port = htons(port);
	if (bind(fd, (struct sockaddr *)&ad, sizeof(ad)) < 0) die("bind");

	struct timespec ts0, ts;
	clock_gettime(CLOCK_MONOTONIC, &ts0);
	t_end = ts0.tv_sec + secs + ts0.tv_nsec / 1e9;

	static char buf[BUFLEN];
	struct iovec iov = { buf, sizeof(buf) };
	struct msghdr mh;
	char ctl[512];
	uint64_t lat_sum = 0, lat_max = 0;
	uint64_t nlat = 0;
	uint64_t n_hw = 0, sum_hw = 0, sum_gap = 0;
	uint32_t last_d = 0;

	while (1) {
		clock_gettime(CLOCK_MONOTONIC, &ts);
		if (ts.tv_sec + ts.tv_nsec / 1e9 >= t_end) break;
		memset(&mh, 0, sizeof(mh));
		mh.msg_iov = &iov; mh.msg_iovlen = 1;
		mh.msg_control = ctl; mh.msg_controllen = sizeof(ctl);
		int n = recvmsg(fd, &mh, 0);
		if (n < 0) { if (errno == EAGAIN) continue; die("recvmsg"); }
		struct timespec rxts; memset(&rxts, 0, sizeof(rxts));
		struct timespec hwts; memset(&hwts, 0, sizeof(hwts));
		int have_hw = 0;
		uint32_t d = 0;
		for (struct cmsghdr *cm = CMSG_FIRSTHDR(&mh); cm;
		     cm = CMSG_NXTHDR(&mh, cm)) {
			if (cm->cmsg_level == SOL_SOCKET &&
			    cm->cmsg_type == SCM_TIMESTAMPNS &&
			    cm->cmsg_len >= CMSG_LEN(sizeof(struct timespec)))
				memcpy(&rxts, CMSG_DATA(cm), sizeof(rxts));
			if (cm->cmsg_level == SOL_SOCKET &&
			    cm->cmsg_type == SCM_TIMESTAMPING &&
			    cm->cmsg_len >= CMSG_LEN(3 * sizeof(struct timespec))) {
				struct timespec t3[3];
				memcpy(&t3, CMSG_DATA(cm), sizeof(t3));
				hwts = t3[2];	/* [0]=sw legacy, [2]=hw raw */
				have_hw = (t3[2].tv_sec || t3[2].tv_nsec);
			}
			if (cm->cmsg_level == SOL_SOCKET &&
			    cm->cmsg_type == SO_RXQ_OVFL &&
			    cm->cmsg_len >= CMSG_LEN(sizeof(uint32_t)))
				memcpy(&d, CMSG_DATA(cm), sizeof(d));
		}
		sum_d += d - last_d;
		last_d = d;
		clock_gettime(CLOCK_REALTIME, &ts);
		if (rxts.tv_sec || rxts.tv_nsec) {
			int64_t ns = (int64_t)(ts.tv_sec - rxts.tv_sec) *
				     1000000000LL + (int64_t)ts.tv_nsec -
				     (int64_t)rxts.tv_nsec;
			uint64_t l = ns < 0 ? 0 : (uint64_t)ns;
			lat_sum += l; nlat++;
			if (l > lat_max) lat_max = l;
			unsigned b = l / 1000;
			hist[b < HIST_US ? b : HIST_US - 1]++;
		}
		if (have_hw && (rxts.tv_sec || rxts.tv_nsec)) {
			/* hw->app crosses the PHC/system boundary:
			 * approximate to the ptp4l/phc2sys sync error;
			 * (sw - hw) is the NIC-ring wait + dispatch */
			int64_t hw_ns = (int64_t)(ts.tv_sec - hwts.tv_sec) *
					1000000000LL + (int64_t)ts.tv_nsec -
					(int64_t)hwts.tv_nsec;
			int64_t gap_ns = (int64_t)(rxts.tv_sec - hwts.tv_sec) *
					 1000000000LL + (int64_t)rxts.tv_nsec -
					 (int64_t)hwts.tv_nsec;
			n_hw++;
			if (hw_ns > 0) sum_hw += (uint64_t)hw_ns;
			if (gap_ns > -1000000 && gap_ns < 1000000)
				sum_gap += gap_ns;
		}
		pkts++;
	}
	drops = sum_d;
	uint64_t acc = 0;
	double p50 = -1, p90 = -1, p99 = -1, p999 = -1;
	for (unsigned b = 0; b < HIST_US; b++) {
		acc += hist[b];
		double us = (double)b + 0.5;
		if (p50 < 0 && acc >= 50 * nlat / 100) p50 = us;
		if (p90 < 0 && acc >= 90 * nlat / 100) p90 = us;
		if (p99 < 0 && acc >= 99 * nlat / 100) p99 = us;
		if (p999 < 0 && acc >= 999 * nlat / 1000) p999 = us;
	}
	printf("k3mot port=%d core=%d consumed=%llu drops=%llu "
	       "mean_us=%.1f p50_us=%.1f p90_us=%.1f p99_us=%.1f "
	       "p99.9_us=%.1f max_us=%.1f hwtstamp=%d hw_ts=%llu "
	       "mean_hw_to_app_us=%.1f mean_sw_minus_hw_us=%.1f\n",
	       port, core, (unsigned long long)pkts, (unsigned long long)drops,
	       nlat ? (double)lat_sum / nlat / 1000.0 : -1.0,
	       p50, p90, p99, p999, lat_max / 1000.0,
	       hwt, (unsigned long long)n_hw,
	       n_hw ? (double)sum_hw / n_hw / 1000.0 : -1.0,
	       n_hw ? (double)sum_gap / n_hw / 1000.0 : -1.0);
	if (p50 >= 0 && p50 < 1.0)
		fprintf(stderr, "GATEWARN k3mot: sw rx->dequeue p50 %.2fus "
			"< 1us - timestamp phase bug suspected\n", p50);
	return 0;
}