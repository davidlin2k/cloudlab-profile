/* k2_rx.c -- pinned UDP consumer for the K2 DDIO-causality measurement.
 *
 * Binds one UDP port and busy-polls it with recvmmsg in fixed batches,
 * touching every payload byte (sums 8-byte words), self-monitored for
 * cycles and cache-misses exactly like bench/calib.c (perf_event_paranoid=2
 * permits self-monitoring). One summary line on exit.
 *
 * The measurement: the driver (k2_ddio.sh) chooses a source port whose RSS
 * hash lands the stream on a chosen RX queue, then runs this consumer pinned
 * to a chosen core. The (queue-CCD x consumer-CCD) matrix of cycles/pkt and
 * misses/pkt is the DDIO causality figure: it shows what pre-DMA steering
 * can move that post-DMA steering structurally cannot.
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
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define BATCH 64
#define BUFLEN 2048

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

static int pe_open(unsigned type, unsigned long long cfg)
{
	struct perf_event_attr a;

	memset(&a, 0, sizeof(a));
	a.type = type;
	a.size = sizeof(a);
	a.config = cfg;
	a.disabled = 0;
	a.exclude_kernel = 1;	/* user-space cost only, like calib.c */
	a.exclude_hv = 1;
	return syscall(__NR_perf_event_open, &a, 0, -1, -1, 0);
}

static double now_s(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + 1e-9 * t.tv_nsec;
}

int main(int argc, char **argv)
{
	int port = 7777, core = 0, secs = 15, i, j, fd, cyc_fd, miss_fd;
	unsigned long long pkts = 0, sum = 0, cyc, miss;
	double t_end;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--port") && i + 1 < argc)
			port = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--core") && i + 1 < argc)
			core = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--secs") && i + 1 < argc)
			secs = atoi(argv[++i]);
		else
			die("usage: k2_rx --port N --core N [--secs 15]");
	}
	pin(core);
	cyc_fd = pe_open(PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES);
	miss_fd = pe_open(PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_MISSES);
	if (cyc_fd < 0 || miss_fd < 0)
		die("perf_event_open (paranoid level?)");

	fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0)
		die("socket");
	int one = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
	int buf = 64 << 20;
	setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buf, sizeof(buf));
	struct sockaddr_in a;
	memset(&a, 0, sizeof(a));
	a.sin_family = AF_INET;
	a.sin_port = htons(port);
	if (bind(fd, (struct sockaddr *)&a, sizeof(a)) < 0)
		die("bind");

	/* Which CPU does the kernel think this socket's queue lives on?
	 * (SO_INCOMING_CPU, 5.2+; -1 if unsupported.) */
	int inc_cpu = -1;
	socklen_t sl = sizeof(inc_cpu);
	getsockopt(fd, SOL_SOCKET, SO_INCOMING_CPU, &inc_cpu, &sl);

	static char bufs[BATCH][BUFLEN] __attribute__((aligned(64)));
	struct mmsghdr mm[BATCH];
	struct iovec iov[BATCH];
	for (i = 0; i < BATCH; i++) {
		iov[i].iov_base = bufs[i];
		iov[i].iov_len = BUFLEN;
		mm[i].msg_hdr.msg_iov = &iov[i];
		mm[i].msg_hdr.msg_iovlen = 1;
	}

	t_end = now_s() + secs;
	while (now_s() < t_end) {
		int n = recvmmsg(fd, mm, BATCH, MSG_WAITFORONE, NULL);
		if (n < 0)
			continue;
		for (i = 0; i < n; i++) {
			int len = mm[i].msg_len;
			unsigned long long *w = (unsigned long long *)bufs[i];
			for (j = 0; j + 8 <= len; j += 8)
				sum += *w++;	/* touch the payload */
			pkts++;
		}
	}
	uint64_t v;
	cyc = miss = 0;
	if (read(cyc_fd, &v, 8) == 8) cyc = v;
	if (read(miss_fd, &v, 8) == 8) miss = v;
	printf("k2rx port=%d core=%d incpu=%d pkts=%llu sum=%llu "
	       "cyc/pkt=%.1f miss/pkt=%.2f\n",
	       port, core, inc_cpu, pkts, sum,
	       pkts ? (double)cyc / pkts : -1.0,
	       pkts ? (double)miss / pkts : -1.0);
	return 0;
}
