/* k5blast.c -- spin-paced UDP blaster for capacity cells (K5CAP).
 * sendmmsg batches back-to-back (the sportgen sendto loop tops out at
 * ~250k pps: syscall-bound, cannot saturate a core). No echo path:
 * this measures the receiver's drain rate under saturation, so the
 * demand side must exceed it. Binds 10.10.1.<sip> with --sport so the
 * authored dport lands on the intended RSS queue.
 * Usage:
 *   k5blast --dip A --sip OCT --sport P --dport Q --n N
 *           [--plen L] [--batch B] [--core C]
 * Prints: [k5blast] sent= wall= rate= enobufs=
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define VLEN 64
#define PL 1600

static void die(const char *m) { perror(m); exit(1); }
static uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

int main(int argc, char **argv)
{
	unsigned long long n = 1000000;
	int plen = 300, batch = VLEN, core = -1;
	int sport = 0, dport = 0, sip = 0;
	char dip[64] = "10.10.1.1";
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--dip")) snprintf(dip, sizeof(dip), "%s", argv[++i]);
		else if (!strcmp(argv[i], "--sip")) sip = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--sport")) sport = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--dport")) dport = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--n")) n = strtoull(argv[++i], NULL, 10);
		else if (!strcmp(argv[i], "--plen")) plen = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--batch")) batch = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--core")) core = atoi(argv[++i]);
		else { fprintf(stderr, "k5blast: unknown arg %s\n", argv[i]); return 1; }
	}
	if (!sport || !dport || !sip || !n) {
		fprintf(stderr, "usage: k5blast --dip A --sip OCT --sport P "
			"--dport Q --n N [--plen L --batch B --core C]\n");
		return 1;
	}
	if (plen < 2 || plen > PL) { fprintf(stderr, "bad plen\n"); return 1; }
	if (core >= 0) {
		cpu_set_t cs; CPU_ZERO(&cs); CPU_SET(core, &cs);
		sched_setaffinity(0, sizeof(cs), &cs);
	}
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0) die("socket");
	int sz = 32 << 20;
	setsockopt(fd, SOL_SOCKET, SO_SNDBUFFORCE, &sz, sizeof(sz));
	char ip[32];
	snprintf(ip, sizeof(ip), "10.10.1.%d", sip);
	struct sockaddr_in s;
	memset(&s, 0, sizeof(s));
	s.sin_family = AF_INET;
	inet_pton(AF_INET, ip, &s.sin_addr);
	s.sin_port = htons(sport);
	if (bind(fd, (struct sockaddr *)&s, sizeof(s)) < 0) die("bind sip");

	static char buf[VLEN][PL];
	for (int i = 0; i < VLEN; i++)
		for (int j = 0; j < plen; j++)
			buf[i][j] = (char)(j & 0xff);
	struct mmsghdr mmsg[VLEN];
	struct iovec iov[VLEN];
	struct sockaddr_in da[VLEN];
	memset(mmsg, 0, sizeof(mmsg));
	memset(da, 0, sizeof(da));
	for (int i = 0; i < VLEN; i++) {
		iov[i].iov_base = buf[i];
		iov[i].iov_len = plen;
		mmsg[i].msg_hdr.msg_iov = &iov[i];
		mmsg[i].msg_hdr.msg_iovlen = 1;
		mmsg[i].msg_hdr.msg_name = &da[i];
		mmsg[i].msg_hdr.msg_namelen = sizeof(da[i]);
		da[i].sin_family = AF_INET;
		da[i].sin_port = htons(dport);
		inet_pton(AF_INET, dip, &da[i].sin_addr);
	}
	uint64_t sent = 0, enobufs = 0;
	uint64_t t0 = now_ns();
	while (sent < n) {
		int want = batch;
		if ((uint64_t)want > n - sent) want = (int)(n - sent);
		int r = sendmmsg(fd, mmsg, want, 0);
		if (r < 0) {
			if (errno == ENOBUFS || errno == EAGAIN) {
				enobufs++;
				continue;
			}
			die("sendmmsg");
		}
		sent += r;
	}
	double wall = (now_ns() - t0) / 1e9;
	printf("[k5blast] dip=%s dport=%d sip=%d sport=%d sent=%llu "
	       "wall=%.2fs rate=%.0f/s enobufs=%llu\n",
	       dip, dport, sip, sport, (unsigned long long)sent, wall,
	       sent / wall, (unsigned long long)enobufs);
	return 0;
}
