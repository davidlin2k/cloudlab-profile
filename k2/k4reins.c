/* k4reins.c -- Reins controller seed: per-core ledger + core-addressed
 * hints. One process, T threads; thread i binds port P_i on core c_i
 * (its queue's softirq core). Each received RPC is echoed back with a
 * 2-byte hint: the port the sender should use next. The ledger (shared
 * mmap) tracks per-port consumed rates over a 100ms window; the hint
 * policy: if my core's rate > 0.8 * knee, hint the least-loaded other
 * port; else stick. Run as root on the RECEIVER. Experiment network only.
 *
 * Build: gcc -Wall -O2 -o k4reins k4reins.c -lpthread
 * Usage: sudo ./k4reins --secs 20 --knee 300000 --cores 0,8 --ports 7777,7779
 * Reply payload: the echoed payload with its last 2 bytes replaced by
 * the hinted port number (big endian). */
#define _GNU_SOURCE
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define MAXP 16
#define BUFLEN 2048
#define WINDOW_MS 100
#define REDIRECT_EVERY 5	/* anti-herding: hint 1-in-N messages */

static void die(const char *m) { perror(m); exit(1); }

/* shared ledger (one process, all threads see it) */
static int g_nports;
static int g_ports[MAXP];
static int g_cgroup[MAXP];		/* thread idx -> core group */
static int g_ncg;			/* number of core groups */
static uint64_t g_cnt[MAXP];		/* consumed pkts per port */
static uint64_t g_prev[MAXP];		/* last snapshot */
static double g_rate[MAXP];		/* pps per port */
static double g_crate[MAXP];		/* pps per core group */
static double g_knee;
static double g_kneeb;			/* byte knee: B/s per core */
static int g_sizeware = 0;		/* 1 = largest-first sender pick */
static int g_srpt = 0;			/* 1 = smalls-first + bulk budget */
static double g_bytes[8];		/* per-group byte rate (port-derived) */
static uint64_t g_bcnt[MAXP], g_bprev[MAXP];
static double g_brate[MAXP];		/* B/s per port */
static int g_bulkport[MAXP];		/* 1 = port carried bulk last window */
static double g_smallrate[8];		/* per-group small-port pkt rate */
static int g_bulk_budget = 3000;	/* per-window bulk echo budget */
static int g_partition = 0;		/* 1 = class-partition placement */
static double g_last_roll = 0;		/* shared roll schedule */
static pthread_mutex_t g_roll_mx = PTHREAD_MUTEX_INITIALIZER;
static uint64_t g_window_id = 0;	/* bumped per roll */
/* conservation ledger (per-port; written only by the port's thread) */
static uint64_t g_echo[MAXP];		/* echoed ok */
static uint64_t g_edrop[MAXP];		/* consumed but not echoed (budget/
					 * malformed) */
static uint64_t g_sfail[MAXP];		/* echo attempted, send failed */
static uint64_t g_rolls = 0;		/* ledger rolls */
#define SPLIT_THRESH 1024
#define MAXSEND 64
#define STICKY_WIN 30		/* windows a migrated sender stays put */

/* per-sender ledger: identified by (sport, sip) of the request */
struct sender {
	uint32_t key;			/* sport | sip<<16 */
	int grp;			/* group it currently sends to */
	int redirect_grp;		/* -1 = stay; else migrate target */
	uint64_t sticky_until;		/* window id until which: no migrate */
	uint64_t cnt, prev;
	uint64_t bytes, prev_bytes;
	double rate, brate;		/* pkts/s, bytes/s */
};
static struct sender g_snd[MAXSEND];

static struct sender *sender_get(uint32_t key)
{
	int slot = (key * 2654435761u) % MAXSEND;
	for (int i = 0; i < MAXSEND; i++) {
		struct sender *s = &g_snd[(slot + i) % MAXSEND];
		if (s->key == key) return s;
		if (s->key == 0) {
			s->key = key;
			s->grp = -1;		/* set on first arrival */
			s->redirect_grp = -1;
			s->sticky_until = 0;
			s->cnt = s->prev = 0;
			s->bytes = s->prev_bytes = 0;
			return s;
		}
	}
	return &g_snd[slot];		/* table full: reuse */
}

/* class-aware placement (sizeware=1): spread SMALL senders one per
 * core (the packet cliff is per-core, so smalls must not share a
 * core's budget), then place BULK senders greedily on the
 * byte-least-loaded core. Sticky senders keep their current group.
 * Idempotent: recomputing every window converges and stays. */
static void place_balanced(void);

/* ledger roll: per-sender rates, then per-group; pick migrations
 * largest-bytes-first while a group is over 0.8 knee and another is
 * under 0.5 knee */
static void ledger_roll(double dt)
{
	/* gate: the ledger rolls once per window; a roll gap under half a
	 * window means a double roll (the bistable race, K4ROLL) */
	if (dt > 0 && dt < WINDOW_MS / 2000.0) {
		fprintf(stderr, "GATEFAIL roll gap %.4fs < %.0fms "
			"(double roll)\n", dt, WINDOW_MS / 2.0);
		exit(2);
	}
	g_rolls++;
	for (int j = 0; j < g_nports; j++) {
		g_rate[j] = (double)(g_cnt[j] - g_prev[j]) / dt;
		g_prev[j] = g_cnt[j];
	}
	for (int g = 0; g < g_ncg; g++) { g_crate[g] = 0; g_bytes[g] = 0; }
	for (int j = 0; j < g_nports; j++) {
		g_crate[g_cgroup[j]] += g_rate[j];
		g_brate[j] = (double)(g_bcnt[j] - g_bprev[j]) / dt;
		g_bprev[j] = g_bcnt[j];
		g_bytes[g_cgroup[j]] += g_brate[j];
		g_bulkport[j] = (g_rate[j] > 100) &&
				(g_brate[j] / g_rate[j] >= SPLIT_THRESH);
	}
	for (int g = 0; g < g_ncg; g++) g_smallrate[g] = 0;
	for (int j = 0; j < g_nports; j++)
		if (!g_bulkport[j])
			g_smallrate[g_cgroup[j]] += g_rate[j];
	for (int i = 0; i < MAXSEND; i++) {
		struct sender *s = &g_snd[i];
		if (!s->key) continue;
		s->rate = (double)(s->cnt - s->prev) / dt;
		s->brate = (double)(s->bytes - s->prev_bytes) / dt;
		s->prev = s->cnt; s->prev_bytes = s->bytes;
	}
	if (getenv("K4DBG")) {
		fprintf(stderr, "[ledger] dt=%.3f sw=%d srpt=%d kneeB=%.1fM "
			"g0=%.1fMB/s g1=%.1fMB/s cr0=%.0fk cr1=%.0fk "
			"sm0=%.0fk sm1=%.0fk\n",
			dt, g_sizeware, g_srpt, g_kneeb / 1e6,
			g_bytes[0] / 1e6,
			g_ncg > 1 ? g_bytes[1] / 1e6 : -1.0,
			g_crate[0] / 1e3, g_ncg > 1 ? g_crate[1] / 1e3 : -1.0,
			g_smallrate[0] / 1e3,
			g_ncg > 1 ? g_smallrate[1] / 1e3 : -1.0);
		if (dt > 0.05)
			for (int i = 0; i < MAXSEND; i++) {
				struct sender *s = &g_snd[i];
				if (!s->key) continue;
				fprintf(stderr, "  [snd] key=%x grp=%d "
					"rate=%.0fk brate=%.1fMB avg=%uB\n",
					s->key, s->grp, s->rate / 1e3,
					s->brate / 1e6,
					s->rate > 1 ? (unsigned)(s->brate / s->rate) : 0);
			}
	}
	if (!g_sizeware) {
		/* blind = packet-count water-fill (aRFS-like): migrate
		 * one sender at a time, largest-bytes first, off any
		 * packet-overloaded group, until it is under half knee */
		for (int g = 0; g < g_ncg; g++) {
			if (g_crate[g] <= 0.8 * g_knee) continue;
			for (int t = 0; t < g_ncg; t++) {
				if (t == g || g_crate[t] >= 0.5 * g_knee)
					continue;
				for (int k = 0; k < MAXSEND &&
				     g_crate[g] > 0.5 * g_knee; k++) {
					struct sender *big = NULL;
					for (int i = 0; i < MAXSEND; i++) {
						struct sender *s = &g_snd[i];
						if (!s->key || s->grp != g ||
						    s->redirect_grp >= 0 ||
						    s->sticky_until > g_window_id)
							continue;
						if (!big || s->brate > big->brate)
							big = s;
					}
					if (!big) break;
					big->redirect_grp = t;
					g_bytes[g] -= big->brate;
					g_bytes[t] += big->brate;
					g_crate[g] -= big->rate;
					g_crate[t] += big->rate;
				}
			}
		}
		return;
	}
	place_balanced();
}

/* class-aware placement (sizeware=1): spread SMALL senders one per
 * core (the packet cliff is per-core, so smalls must not share a
 * core's budget), then place BULK senders greedily on the
 * byte-least-loaded core. Sticky senders keep their current group.
 * Idempotent: recomputing every window converges and stays. */
static void place_balanced(void)
{
	double L[8];
	int assigned[MAXSEND];
	for (int g = 0; g < g_ncg; g++) L[g] = 0;
	for (int i = 0; i < MAXSEND; i++) assigned[i] = -1;
	for (int i = 0; i < MAXSEND; i++) {
		struct sender *s = &g_snd[i];
		if (!s->key) continue;
		if (s->sticky_until > g_window_id && s->grp >= 0) {
			assigned[i] = s->grp;
			L[s->grp] += s->brate;
		}
	}
	if (g_partition) {
		/* CLASS PARTITION: all smalls -> group 0; all bulks
		 * greedily balanced across the remaining groups. The
		 * dport->queue authoring makes the split real: a
		 * steered sender's flows land only on its group's
		 * queues, so the classes stop sharing cores AND
		 * softirq pipelines. s->grp is the PLACEMENT's model
		 * (arrivals never flip it); hints derive from it. */
		for (int i = 0; i < MAXSEND; i++) {
			struct sender *s = &g_snd[i];
			if (!s->key) continue;
			int is_bulk = (s->rate > 1000) &&
			    (s->brate / s->rate >= SPLIT_THRESH);
			int t = is_bulk ? 1 % g_ncg : 0;
			if (s->grp != t) s->grp = t;
		}
		return;
	}
	for (int pass = 0; pass < 2; pass++) {
		for (int n = 0; n < MAXSEND; n++) {
			struct sender *best = NULL;
			for (int i = 0; i < MAXSEND; i++) {
				struct sender *s = &g_snd[i];
				if (!s->key || assigned[i] >= 0) continue;
				int is_bulk = (s->rate > 1000) &&
				    (s->brate / s->rate >= SPLIT_THRESH);
				if (is_bulk != (pass == 1)) continue;
				if (pass == 0) {
					if (!best || s->rate > best->rate)
						best = s;
				} else {
					if (!best || s->brate > best->brate)
						best = s;
				}
			}
			if (!best) break;
			int t = 0;
			for (int g = 1; g < g_ncg; g++)
				if (L[g] < L[t]) t = g;
			int bi = best - g_snd;
			assigned[bi] = t;
			L[t] += best->brate;
			/* placement owns the model; redirect tells the
			 * arrival path a move is pending (sticky on
			 * completion) */
			if (t != best->grp && best->redirect_grp < 0)
				best->redirect_grp = t;
			best->grp = t;
		}
	}
}

static double now_s(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

struct thr_arg { int grp; int core; int secs; int nports; int pidx[MAXP]; };
#define BULK_BUDGET 3000	/* max bulk echoes per 100ms window when over */

static void *thr(void *ap)
{
	struct thr_arg *a = ap;
#define VLEN 64
	static __thread char bufs[MAXP][VLEN][BUFLEN];
	static __thread struct iovec iovs[MAXP][VLEN];
	static __thread struct mmsghdr mmsg[MAXP][VLEN];
	static __thread struct sockaddr_in froms[MAXP][VLEN];
	static __thread char out[MAXP][VLEN][BUFLEN];
	static __thread struct mmsghdr smmsg[MAXP][VLEN];
	static __thread struct iovec siov[MAXP][VLEN];
	int fds[MAXP];
	int one = 1, sz = 32 << 20;
	cpu_set_t cs;
	double t_end;
	uint64_t mine = 0;
	uint64_t bulk_echoed = 0, bulk_dropped = 0;
	uint64_t my_window = 0;
	int cur_budget = g_bulk_budget;
	uint64_t port_tok[MAXP];	/* packet tokens per my-port */
	for (int k = 0; k < MAXP; k++) port_tok[k] = (uint64_t)-1;

	CPU_ZERO(&cs); CPU_SET(a->core, &cs);
	if (sched_setaffinity(0, sizeof(cs), &cs) < 0) die("setaffinity");
	for (int k = 0; k < a->nports; k++) {
		fds[k] = socket(AF_INET, SOCK_DGRAM, 0);
		setsockopt(fds[k], SOL_SOCKET, SO_REUSEADDR, &one, 4);
		/* SO_RCVBUF is clamped by rmem_max (~208KB = ~540 pkts);
		 * force the full buffer: the deep per-port queue is what
		 * absorbs the redirect transient */
		if (setsockopt(fds[k], SOL_SOCKET, SO_RCVBUFFORCE, &sz, sizeof(sz)) < 0)
			setsockopt(fds[k], SOL_SOCKET, SO_RCVBUF, &sz, sizeof(sz));
		if (setsockopt(fds[k], SOL_SOCKET, SO_SNDBUFFORCE, &sz, sizeof(sz)) < 0)
			setsockopt(fds[k], SOL_SOCKET, SO_SNDBUF, &sz, sizeof(sz));
		struct sockaddr_in ad;
		memset(&ad, 0, sizeof(ad));
		ad.sin_family = AF_INET;
		ad.sin_addr.s_addr = INADDR_ANY;
		ad.sin_port = htons(g_ports[a->pidx[k]]);
		if (bind(fds[k], (struct sockaddr *)&ad, sizeof(ad)) < 0) die("bind");
	}

	t_end = now_s() + a->secs;
	if (g_last_roll == 0) g_last_roll = now_s();
	int ord[MAXP];			/* drain order: smalls first */
	for (int k = 0; k < a->nports; k++) ord[k] = k;
	struct timespec rto = { .tv_sec = 0, .tv_nsec = 2000000 };
	while (now_s() < t_end) {
		/* wall-clock ledger windows: roll on schedule even when
		 * no packets arrive (idle tail must not freeze the
		 * ledger); the roll check runs every loop iteration */
		double tnow = now_s();
		if (tnow - g_last_roll >= WINDOW_MS / 1000.0) {
			pthread_mutex_lock(&g_roll_mx);
			if (tnow - g_last_roll >= WINDOW_MS / 1000.0) {
				ledger_roll(tnow - g_last_roll);
				g_last_roll = tnow;
				g_window_id++;
			}
			pthread_mutex_unlock(&g_roll_mx);
		}
		for (int kk = 0; kk < a->nports; kk++) {
			int k = ord[kk];
			int j = a->pidx[k];
			int mygrp = g_cgroup[j];
			int overload = (g_bytes[mygrp] > 0.8 * g_kneeb) ||
				       (g_crate[mygrp] > 0.8 * g_knee);
			/* PORT-LEVEL ADMISSION via tokens: each bulk-class
			 * port may drain at most its share of the group's
			 * residual packet capacity per window; beyond that
			 * the port is left undrained and its packets rot
			 * in the kernel queue. Small ports always drain
			 * (tokens unlimited). Tokens keep a sampling flow
			 * so the ledger keeps measuring demand. */
			if (g_srpt && g_bulkport[j] && port_tok[k] <= 0)
				continue;
			int want = VLEN;
			if (g_srpt && g_bulkport[j] &&
			    port_tok[k] < (uint64_t)VLEN)
				want = (int)port_tok[k];
			for (int i = 0; i < VLEN; i++) {
				iovs[k][i].iov_base = bufs[k][i];
				iovs[k][i].iov_len = BUFLEN;
				memset(&mmsg[k][i].msg_hdr, 0, sizeof(mmsg[k][i].msg_hdr));
				mmsg[k][i].msg_hdr.msg_iov = &iovs[k][i];
				mmsg[k][i].msg_hdr.msg_iovlen = 1;
				mmsg[k][i].msg_hdr.msg_name = &froms[k][i];
				mmsg[k][i].msg_hdr.msg_namelen = sizeof(froms[k][i]);
				mmsg[k][i].msg_len = 0;
			}
			int got = recvmmsg(fds[k], mmsg[k], want,
					   MSG_DONTWAIT, &rto);
			if (got <= 0) continue;
			if (g_srpt && g_bulkport[j])
				port_tok[k] -= got;
			g_cnt[j] += got; mine += got;
			double t = now_s();
			for (int i = 0; i < got; i++) {
				/* gate: msg_len must be nonzero (the
				 * K4RACE prep-loop zeroing signature) */
				if (mmsg[k][i].msg_len == 0) {
					fprintf(stderr, "GATEFAIL msg_len==0 "
						"port=%d idx=%d\n",
						g_ports[j], i);
					exit(2);
				}
				uint32_t key = (uint32_t)froms[k][i].sin_port |
					((ntohl(froms[k][i].sin_addr.s_addr) & 0xff) << 16);
				struct sender *s = sender_get(key);
				s->cnt++; s->bytes += mmsg[k][i].msg_len;
				g_bcnt[j] += mmsg[k][i].msg_len;
				if (getenv("K4DBG") && (s->cnt & 0x3fff) == 1)
					fprintf(stderr, "  [pkt] key=%x "
						"len=%u fromport=%u\n",
						key, mmsg[k][i].msg_len,
						ntohs(froms[k][i].sin_port));
				if (s->grp != mygrp && s->redirect_grp >= 0 &&
				    mygrp == s->redirect_grp) {
					/* migration completed: clear the
					 * pending redirect, go sticky. The
					 * PLACEMENT's grp stands - straggler
					 * arrivals on the old port must not
					 * flip it (they would make the other
					 * core's echo emit a stay/return
					 * hint and re-churn the sender). */
					s->redirect_grp = -1;
					s->sticky_until =
						g_window_id + STICKY_WIN;
				}
			}
			if (my_window != g_window_id) {
				/* window bookkeeping: reset per-window
				 * budget/token state (the roll itself
				 * now happens at the top of the loop) */
				my_window = g_window_id;
				bulk_echoed = 0;	/* window reset */
				/* demand-adaptive bulk budget: the group's
				 * residual packet RATE after smalls, converted
				 * to packets-per-window and split across this
				 * group's bulk-class ports */
				double res = 0.85 * g_knee - g_smallrate[mygrp];
				if (res < 0) res = 0;
				cur_budget = (int)(res * WINDOW_MS / 1000.0);
					/* drain order: smalls first */
					int no = 0;
					for (int k = 0; k < a->nports; k++)
						if (!g_bulkport[a->pidx[k]])
							ord[no++] = k;
					for (int k = 0; k < a->nports; k++)
						if (g_bulkport[a->pidx[k]])
							ord[no++] = k;
					int nbulk = 0;
					for (int k = 0; k < a->nports; k++)
						if (g_bulkport[a->pidx[k]]) nbulk++;
					if (getenv("K4DBG"))
						fprintf(stderr, "  [tok] grp=%d "
							"res=%.0fk nbulk=%d "
							"tok/window=%d\n", mygrp,
							res / 1e3, nbulk,
							cur_budget);
				for (int k = 0; k < a->nports; k++) {
					if (g_bulkport[a->pidx[k]] && nbulk > 0)
						port_tok[k] = (uint64_t)cur_budget
							      / (uint64_t)nbulk;
					else
						port_tok[k] = (uint64_t)-1;
				}
			}
			if (getenv("K4DBG") && overload && !bulk_echoed)
				fprintf(stderr, "  [ovl] grp=%d bytes=%.1fMB "
					"crate=%.0fk srpt=%d\n", mygrp,
					g_bytes[mygrp] / 1e6,
					g_crate[mygrp] / 1e3, g_srpt);
			int nsm = 0, nbk = 0;
			for (int i = 0; i < got; i++) {
				uint32_t key = (uint32_t)froms[k][i].sin_port |
					((ntohl(froms[k][i].sin_addr.s_addr) & 0xff) << 16);
				struct sender *s = sender_get(key);
				int hi = (s->redirect_grp >= 0) ?
					s->redirect_grp : s->grp;
				int n = mmsg[k][i].msg_len;
				if (n < 2) {
					g_edrop[j]++;	/* malformed:
							 * consumed, not
							 * echoed */
					continue;
				}
				int is_bulk = (n >= SPLIT_THRESH);
				/* SRPT + admission: under overload, echo
				 * smalls first and cap bulk echoes per
				 * window; capped bulks are dropped (the
				 * sender counts them censored) */
				if (g_srpt && is_bulk && overload &&
				    bulk_echoed >= cur_budget) {
					bulk_dropped++;
					g_edrop[j]++;
					continue;
				}
				if (is_bulk) bulk_echoed++;
				if (getenv("K4DBG") && is_bulk &&
				    (bulk_echoed & 0x3ff) == 1)
					fprintf(stderr, "  [blk] grp=%d n=%u "
						"ovl=%d be=%llu\n", mygrp, n,
						overload,
						(unsigned long long)bulk_echoed);
				/* smalls fill [0..nsm), bulks the tail */
				int tgt = is_bulk ?
					(VLEN - 1 - (nbk++)) : (nsm++);
				memcpy(out[k][tgt], bufs[k][i], n);
				out[k][tgt][n - 2] = (uint8_t)0xff;
				out[k][tgt][n - 1] = (uint8_t)hi;
				siov[k][tgt].iov_base = out[k][tgt];
				siov[k][tgt].iov_len = n;
				memset(&smmsg[k][tgt].msg_hdr, 0,
				       sizeof(smmsg[k][tgt].msg_hdr));
				smmsg[k][tgt].msg_hdr.msg_iov = &siov[k][tgt];
				smmsg[k][tgt].msg_hdr.msg_iovlen = 1;
				smmsg[k][tgt].msg_hdr.msg_name = &froms[k][i];
				smmsg[k][tgt].msg_hdr.msg_namelen = sizeof(froms[k][i]);
				smmsg[k][tgt].msg_len = 0;
			}
			if (nsm) {
				int r = sendmmsg(fds[k], smmsg[k], nsm,
						 MSG_DONTWAIT);
				if (r > 0) g_echo[j] += r;
				g_sfail[j] += nsm - (r > 0 ? r : 0);
			}
			if (nbk) {
				int r = sendmmsg(fds[k], &smmsg[k][VLEN - nbk],
						 nbk, MSG_DONTWAIT);
				if (r > 0) g_echo[j] += r;
				g_sfail[j] += nbk - (r > 0 ? r : 0);
			}
		}
	}
	for (int k = 0; k < a->nports; k++)
		printf("[k4reins] port=%d core=%d grp=%d consumed=%llu\n",
		       g_ports[a->pidx[k]], a->core, a->grp,
		       (unsigned long long)(g_cnt[a->pidx[k]]));
	printf("[k4reins] grp=%d core=%d total=%llu bulk_dropped=%llu\n",
	       a->grp, a->core, (unsigned long long)mine,
	       (unsigned long long)bulk_dropped);
	return NULL;
}

int main(int argc, char **argv)
{
	int secs = 20;
	double knee = 300000;
	char corelist[256] = "", portlist[256] = "";
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--secs")) secs = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--knee")) knee = atof(argv[++i]);
		else if (!strcmp(argv[i], "--kneeb")) g_kneeb = atof(argv[++i]);
		else if (!strcmp(argv[i], "--sizeware")) g_sizeware = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--srpt")) g_srpt = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--partition")) g_partition = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--budget")) g_bulk_budget = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--cores")) snprintf(corelist, sizeof(corelist), "%s", argv[++i]);
		else if (!strcmp(argv[i], "--ports")) snprintf(portlist, sizeof(portlist), "%s", argv[++i]);
		else { fprintf(stderr, "k4reins: unknown arg %s\n", argv[i]); return 1; }
	}
	if (!corelist[0] || !portlist[0]) {
		fprintf(stderr, "usage: k4reins --secs S --knee PPS --kneeb BPS --cores 0,8 --ports 7777,7779\n");
		return 1;
	}
	if (g_kneeb <= 0) g_kneeb = knee * 300.0;	/* default: 300B avg */
	if (g_bulk_budget < 0) g_bulk_budget = (int)(0.85 * knee);
	g_nports = 0;
	char *save = NULL;
	for (char *tok = strtok_r(corelist, ",", &save); tok && g_nports < MAXP;
	     tok = strtok_r(NULL, ",", &save))
		g_ports[g_nports++] = atoi(tok);	/* cores first */
	int nc = g_nports;
	int cores[MAXP];
	memcpy(cores, g_ports, sizeof(cores));
	g_nports = 0;
	save = NULL;
	for (char *tok = strtok_r(portlist, ",", &save); tok && g_nports < nc;
	     tok = strtok_r(NULL, ",", &save))
		g_ports[g_nports++] = atoi(tok);
	if (g_nports != nc) { fprintf(stderr, "k4reins: cores/ports count mismatch\n"); return 1; }
	g_knee = knee;
	/* core groups: first occurrence of each distinct core */
	g_ncg = 0;
	for (int i = 0; i < g_nports; i++) {
		g_cgroup[i] = g_ncg;
		for (int j = 0; j < i; j++)
			if (cores[j] == cores[i]) { g_cgroup[i] = g_cgroup[j]; break; }
		if (g_cgroup[i] == g_ncg) g_ncg++;
	}

	printf("[k4reins] %d ports, %d core groups, knee=%.0f pps, secs=%d\n",
	       g_nports, g_ncg, knee, secs);
	double t_start = now_s();
	/* one thread per distinct core, multiplexing that core's ports */
	pthread_t th[MAXP];
	struct thr_arg ta[MAXP];
	int nthr = 0;
	for (int g = 0; g < g_ncg; g++) {
		ta[g].grp = g; ta[g].secs = secs; ta[g].nports = 0;
		for (int i = 0; i < g_nports; i++) {
			if (g_cgroup[i] != g) continue;
			ta[g].pidx[ta[g].nports++] = i;
		}
		/* the thread's core = the core of the first port in the group */
		int first = -1;
		for (int i = 0; i < g_nports; i++)
			if (g_cgroup[i] == g) { first = i; break; }
		ta[g].core = cores[first];
		if (pthread_create(&th[g], NULL, thr, &ta[g])) die("pthread");
		nthr++;
	}
	for (int g = 0; g < nthr; g++)
		pthread_join(th[g], NULL);
	/* conservation gates: per port, consumed == echoed + echo_dropped +
	 * send_failed; the ledger must roll ~once per window. Any
	 * violation discards the run (exit != 0). */
	int bad = 0;
	for (int i = 0; i < g_nports; i++) {
		uint64_t cons = g_cnt[i];
		uint64_t acc = g_echo[i] + g_edrop[i] + g_sfail[i];
		printf("[gate] port=%d consumed=%llu echoed=%llu "
		       "echo_dropped=%llu send_failed=%llu %s\n",
		       g_ports[i], (unsigned long long)cons,
		       (unsigned long long)g_echo[i],
		       (unsigned long long)g_edrop[i],
		       (unsigned long long)g_sfail[i],
		       cons == acc ? "OK" : "FAIL");
		if (cons != acc) bad = 1;
	}
	double exp_rolls = (now_s() - t_start) / (WINDOW_MS / 1000.0);
	/* margin 4: thread start lags t_start by the spawn+first-batch
	 * skew (~0.4s under load) and the last boundary may fall inside
	 * the final gap; -4 trips only on genuinely frozen ledgers */
	printf("[gate] rolls=%llu expected>=%.0f %s\n",
	       (unsigned long long)g_rolls, exp_rolls - 4.0,
	       (g_rolls >= (uint64_t)(exp_rolls - 4.0) && g_rolls > 0) ?
	       "OK" : "FAIL");
	if (g_rolls == 0 || (double)g_rolls < exp_rolls - 4.0) bad = 1;
	if (bad) {
		fprintf(stderr, "GATEFAIL conservation violated - "
			"DISCARD RUN\n");
		return 2;
	}
	return 0;
}