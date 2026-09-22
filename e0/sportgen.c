/* sportgen.c -- raw 4-tuple hash probe emitter for the E0 actuation gate.
 *
 * Sends N hand-built packets with a chosen (sip, dip, sport, dport) tuple so
 * the receiver's NIC RSS hash can be predicted and verified against per-queue
 * counters. Three wire shapes:
 *   udp  UDP/IPv4, UDP checksum 0 (legal for IPv4). 4-tuple hash.
 *   tcp  TCP-shaped packets (PSH|ACK, fixed seq). Same 4-tuple hash class as
 *        UDP; this is the shape HomaModule's TCP-hijack mode intercepts.
 *   146  Bare IP payload with protocol 146 = IPPROTO_HOMA.
 *        Expected to hash L3-only on most NICs -- the informational probe.
 *
 * --plen sets the L4 payload size (1..1400): the gate uses small packets and
 * K2 (DDIO causality) uses 1400 to exercise the payload term.
 *
 * Rate limiting: --batch packets, then usleep(--pause) microseconds, so a
 * single core can pace the stream without becoming the bottleneck.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#define PAYLOAD 32
#define DEF_BATCH 200
#define DEF_PAUSE 400
#define PROTO_HOMA 146

/* Hand-built L4 headers: no struct padding or bitfield guesswork. */
struct udp_wire {
	unsigned short sport, dport, len, csum;
} __attribute__((packed));

struct tcp_wire {
	unsigned short sport, dport;
	unsigned int seq, ack;
	unsigned char off, flags;
	unsigned short win, csum, urg;
} __attribute__((packed));

struct cfg {
	struct in_addr saddr, daddr;
	unsigned short sport, dport;
	int n, batch, pause, proto;
	unsigned plen;			/* L4 payload bytes (default 32) */
	const char *iface, *sip, *dip;
};

static void
die(const char *why)
{
	fprintf(stderr, "sportgen: %s: %s\n", why, strerror(errno));
	exit(1);
}

static void
usage(const char *why)
{
	fprintf(stderr,
"usage: sportgen --dip IP --dport N --sport N [--n N] [--plen 1..1400]\n"
"       [--proto udp|146|tcp] [--batch N] [--pause us] [--iface IF] [--sip IP]\n"
"       (%s)\n", why);
	exit(2);
}

/* Internet checksum over a buffer (even or odd length). */
static unsigned short
csum16(const void *buf, int len)
{
	const unsigned short *w = buf;
	unsigned int sum = 0;

	while (len > 1) {
		sum += *w++;
		len -= 2;
	}
	if (len == 1)
		sum += *(const unsigned char *)w;
	while (sum >> 16)
		sum = (sum & 0xffff) + (sum >> 16);
	return ~sum;
}

/* Address the kernel would pick to reach dst (learned via a throwaway UDP
 * connect): the experiment interface's source address. */
static struct in_addr
find_saddr(struct in_addr dst)
{
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	struct sockaddr_in a;
	socklen_t alen = sizeof(a);

	if (fd < 0)
		die("socket(UDP)");
	memset(&a, 0, sizeof(a));
	a.sin_family = AF_INET;
	a.sin_addr = dst;
	a.sin_port = htons(9);
	if (connect(fd, (struct sockaddr *)&a, sizeof(a)) < 0)
		die("connect(learn-saddr)");
	if (getsockname(fd, (struct sockaddr *)&a, &alen) < 0)
		die("getsockname");
	close(fd);
	return a.sin_addr;
}

int
main(int argc, char **argv)
{
	struct cfg cfg;
	struct sockaddr_in dst;
	unsigned char pkt[2048];
	struct iphdr *ip;
	struct udp_wire *udp;
	struct tcp_wire *tcp;
	int fd, i, one, l4len, total, sndbuf;
	char sipstr[INET_ADDRSTRLEN], dipstr[INET_ADDRSTRLEN];

	memset(&cfg, 0, sizeof(cfg));
	cfg.n = 20000;
	cfg.batch = DEF_BATCH;
	cfg.pause = DEF_PAUSE;
	cfg.proto = IPPROTO_UDP;
	cfg.plen = PAYLOAD;
	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--dip") && i + 1 < argc)
			cfg.dip = argv[++i];
		else if (!strcmp(argv[i], "--dport") && i + 1 < argc)
			cfg.dport = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--sport") && i + 1 < argc)
			cfg.sport = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--n") && i + 1 < argc)
			cfg.n = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--proto") && i + 1 < argc) {
			i++;
			if (!strcmp(argv[i], "udp"))
				cfg.proto = IPPROTO_UDP;
			else if (!strcmp(argv[i], "tcp"))
				cfg.proto = IPPROTO_TCP;
			else if (!strcmp(argv[i], "146"))
				cfg.proto = PROTO_HOMA;
			else
				usage("bad --proto (want udp|146|tcp)");
		} else if (!strcmp(argv[i], "--iface") && i + 1 < argc)
			cfg.iface = argv[++i];
		else if (!strcmp(argv[i], "--sip") && i + 1 < argc)
			cfg.sip = argv[++i];
		else if (!strcmp(argv[i], "--batch") && i + 1 < argc)
			cfg.batch = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--pause") && i + 1 < argc)
			cfg.pause = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--plen") && i + 1 < argc) {
			cfg.plen = strtoul(argv[++i], NULL, 0);
			if (cfg.plen < 1 || cfg.plen > 1400)
				usage("--plen must be 1..1400");
		} else
			usage(argv[i]);
	}
	if (!cfg.dip || !cfg.sport || !cfg.dport)
		usage("--dip, --sport and --dport are required");
	if (inet_aton(cfg.dip, &cfg.daddr) == 0)
		usage("bad --dip address");
	if (cfg.sip && inet_aton(cfg.sip, &cfg.saddr) == 0)
		usage("bad --sip address");
	if (!cfg.sip)
		cfg.saddr = find_saddr(cfg.daddr);

	l4len = 0;
	if (cfg.proto == IPPROTO_UDP)
		l4len = sizeof(*udp);
	else if (cfg.proto == IPPROTO_TCP)
		l4len = sizeof(*tcp);
	total = sizeof(*ip) + l4len + cfg.plen;
	if (total > (int)sizeof(pkt))
		die("packet grew?");

	fd = socket(AF_INET, SOCK_RAW, IPPROTO_RAW);
	if (fd < 0)
		die("socket(IPPROTO_RAW) (need root / CAP_NET_RAW)");
	one = 1;
	if (setsockopt(fd, IPPROTO_IP, IP_HDRINCL, &one, sizeof(one)) < 0)
		die("setsockopt(IP_HDRINCL)");
	if (cfg.iface &&
	    setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, cfg.iface,
		       strlen(cfg.iface) + 1) < 0)
		die("setsockopt(SO_BINDTODEVICE) (need root?)");
	sndbuf = 1 << 20;
	setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));

	memset(&dst, 0, sizeof(dst));
	dst.sin_family = AF_INET;
	dst.sin_addr = cfg.daddr;

	memset(pkt, 0, sizeof(pkt));
	memcpy(pkt + 20 + l4len, "E0GATE", 6);
	for (i = 6; i < (int)cfg.plen; i++)
		pkt[20 + l4len + i] = (unsigned char)(0x40 + i);

	ip = (struct iphdr *)pkt;
	ip->ihl = 5;
	ip->version = 4;
	ip->ttl = 64;
	ip->protocol = cfg.proto;
	ip->tot_len = htons(total);
	ip->saddr = cfg.saddr.s_addr;
	ip->daddr = cfg.daddr.s_addr;

	udp = (struct udp_wire *)(pkt + 20);
	tcp = (struct tcp_wire *)(pkt + 20);
	if (cfg.proto == IPPROTO_UDP) {
		udp->sport = htons(cfg.sport);
		udp->dport = htons(cfg.dport);
		udp->len = htons(l4len + cfg.plen);
		udp->csum = 0;		/* 0 means "none" for IPv4 UDP */
	} else if (cfg.proto == IPPROTO_TCP) {
		unsigned int sum = 0;
		unsigned int sa = cfg.saddr.s_addr, da = cfg.daddr.s_addr;
		int L = l4len + cfg.plen, j;

		tcp->sport = htons(cfg.sport);
		tcp->dport = htons(cfg.dport);
		tcp->seq = htonl(0x45304741);	/* fixed: hash probes need
						 * no real stream */
		tcp->ack = 0;
		tcp->off = 5;
		tcp->flags = 0x18;		/* PSH | ACK */
		tcp->win = htons(65535);
		/* pseudo-header checksum, computed inline over l4+payload */
		sum += (sa >> 16) & 0xffff; sum += sa & 0xffff;
		sum += (da >> 16) & 0xffff; sum += da & 0xffff;
		sum += htons(IPPROTO_TCP);
		sum += htons(L);
		for (j = 0; j + 1 < L; j += 2)
			sum += *(const unsigned short *)(pkt + 20 + j);
		if (L & 1)
			sum += *(const unsigned char *)(pkt + 20 + L - 1);
		while (sum >> 16)
			sum = (sum & 0xffff) + (sum >> 16);
		tcp->csum = ~sum & 0xffff;
	}

	for (i = 0; i < cfg.n; i++) {
		ip->id = htons((0xe000 + i) & 0xffff);
		ip->check = 0;
		ip->check = csum16(ip, sizeof(*ip));
		if (sendto(fd, pkt, total, 0, (struct sockaddr *)&dst,
			   sizeof(dst)) < 0)
			die("sendto");
		if ((i + 1) % cfg.batch == 0)
			usleep(cfg.pause);
	}
	close(fd);

	if (!inet_ntop(AF_INET, &cfg.saddr, sipstr, sizeof(sipstr)) ||
	    !inet_ntop(AF_INET, &cfg.daddr, dipstr, sizeof(dipstr)))
		die("inet_ntop");
	printf("sportgen: sent %d proto %d packets %s:%u -> %s:%u "
	       "(batch %d, pause %dus, plen %u)\n",
	       cfg.n, cfg.proto, sipstr, cfg.sport, dipstr, cfg.dport,
	       cfg.batch, cfg.pause, cfg.plen);
	return 0;
}
