#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause

"""toeplitz.py - reference Toeplitz RSS calculator for the Reins E0 gate.

Predicts, for one (sip, dip, sport, dport) 4-tuple, the 32-bit Toeplitz hash
a ConnectX-6 (mlx5) receiver computes, and the RX queue that hash selects
through the RSS indirection table dumped by `ethtool -x <iface>`.  This is
what e0_gate.sh verifies empirically: if sport -> queue is deterministic,
the Reins mechanism (receiver steers each message to a core via its
ephemeral source port) is actuated by plain RSS.

Input tuple, MSB-first (network byte order = on-the-wire order):
    4 bytes sip + 4 bytes dip + 2 bytes sport + 2 bytes dport
Hash = standard Toeplitz over that stream with the 40-byte key (also read
MSB-first).  The indirection table is indexed by the LOWEST log2(n) bits of
the 32-bit result:

    queue = indir[hash & (indir_size - 1)]     # indir_size = rk, power of two

The low-bits convention is what Linux and DPDK assume (DPDK test_thash.c
checks `hash & HASH_MSK(reta_sz)`, HASH_MSK(reta_sz) = (1 << reta_sz) - 1);
mlx5 follows it, feeding its 32-bit Toeplitz result into the RQT.

mlx5 quirks found in the driver/ethtool sources (citations in README):
 * The default key is RANDOMIZED PER BOOT: mlx5e_rss_params_init() calls
   netdev_rss_key_fill() (Linux drivers/net/ethernet/mellanox/mlx5/core/en/
   rss.c).  Never hardcode a key; dump `ethtool -x` at run time.  The key
   ethtool prints is consumed verbatim by mlx5 hardware (mlx5e_rss_set_rxfh()
   memcpy's it unchanged; reversed consumption is an older-mlx4 quirk).
   --key-order rev remains available in case an adapter does consume the
   dump reversed.
 * Newer ethtool prints the header as "RSS hash key *default*:" or
   "Key *default*:"; the parser accepts any "<...>hash key<markers>:" header
   with colon- or space-separated hex on that and following lines.
 * mlx5e defaults to Toeplitz (ETH_RSS_HASH_TOP).  Kernels newer than
   ~6.12 also default to SYMMETRIC hash (rss->hash.symmetric = true in
   en/rss.c); Ubuntu 24.04's 6.8 kernel does not.  Symmetric hashing is
   still deterministic but is not the plain 4-tuple computation; the gate
   tries to disable it via ethtool and otherwise calibrates among
   prediction modes empirically (--all-modes covers them).
 * mlx5's RQT (indir table) is padded to a power of two that can exceed the
   channel count; extra entries map to queue 0.  We read only what ethtool
   dumps, so padding is handled for us.
 * For packets without a recognized L4 header (IP protocol 146 = Homa) mlx5
   can only hash L3 fields, so the queue is fixed by (sip, dip) alone and
   does NOT follow the source port.  That is the expected proto-146 failure
   Reins gates on; stream_l3() models it.

Selftest (--selftest) checks the core computation against the five IPv4
tuples of the Intel 82599 "RSS Verification Suite" (datasheet 7.1.2.8.3) as
embedded in DPDK app/test/test_thash.c - both the 4-tuple and L3-only
hashes - plus construction self-consistency checks.  With the 82599 vectors
the implementation is externally verified; the remaining checks would
otherwise be self-consistency only.
"""

import argparse
import re
import struct
import sys

# Intel 82599 datasheet 7.1.2.8.3 suite, as embedded in DPDK
# app/test/test_thash.c (default_rss_key[], v4_tbl[]).
V4_VECTORS = [
	# (src_ip, dst_ip, sport, dport, hash_l3, hash_l3l4)
	("66.9.149.187", "161.142.100.80", 2794, 1766, 0x323e8fc2, 0x51ccc178),
	("199.92.111.2", "65.69.140.83", 14230, 4739, 0xd718262a, 0xc626b0ea),
	("24.19.198.95", "12.22.207.184", 12898, 38024, 0xd2d0a5de, 0x5c2b394a),
	("38.27.205.30", "209.142.163.6", 48228, 2217, 0x82989176, 0xafc7327f),
	("153.39.163.191", "202.188.127.2", 44251, 1303, 0x5d1809c5, 0x10e828a2),
]
DPDK_KEY = ("6d5a56da255b0ec24167253d43a38fb0d0ca2bcbae7b30b4"
			"77cb2da38030f20c6a42b73bbeac01fa")

# Prediction modes swept by --all-modes: <key-order>[_<canonicalization>].
MODES = ("fwd", "fwd_xor", "fwd_swap", "rev", "rev_xor", "rev_swap")


def toeplitz(key, data):
	"""Toeplitz RSS hash.  key: bytes; data: input bytes.  Returns the
	32-bit hash: XOR over every set input bit i of the 32-bit key window
	starting at bit i of the MSB-first keystream."""
	ks = int.from_bytes(key, "big")
	kbits = len(key) * 8
	h = 0
	for i in range(len(data) * 8):
		if data[i >> 3] & (0x80 >> (i & 7)):
			h ^= (ks >> (kbits - 32 - i)) & 0xFFFFFFFF
	return h


def inet_bytes(s):
	parts = s.split(".")
	if len(parts) != 4:
		raise ValueError("bad IPv4 address %r" % (s,))
	return bytes(int(x) & 0xFF for x in parts)


def stream4(sip, dip, sport, dport):
	"""Wire-order input stream for an IPv4 4-tuple."""
	return (inet_bytes(sip) + inet_bytes(dip)
			+ struct.pack(">HH", sport & 0xFFFF, dport & 0xFFFF))


def stream_l3(sip, dip):
	"""Address-only stream: what a NIC hashes with no L4 header (proto 146)."""
	return inet_bytes(sip) + inet_bytes(dip)


def stream_xor_symmetric(sip, dip, sport, dport):
	"""Best-effort stand-in for symmetric Toeplitz: hash over the pairwise
	XOR-folded tuple (sip^dip twice, sport^dport twice).  Symmetric by
	construction; mlx5's rx_hash_symmetric transform is not precisely
	documented, so e0_gate.sh calibrates prediction modes empirically."""
	sb, db = inet_bytes(sip), inet_bytes(dip)
	x = bytes(a ^ b for a, b in zip(sb, db))
	y = struct.pack(">H", (sport ^ dport) & 0xFFFF)
	return x + x + y + y


def stream_swapped_symmetric(sip, dip, sport, dport):
	"""Canonical-order variant: swap (sip,sport) with (dip,dport) so both
	directions yield the same stream."""
	sb, db = inet_bytes(sip), inet_bytes(dip)
	if sb > db or (sb == db and sport > dport):
		sb, db, sport, dport = db, sb, dport, sport
	return sb + db + struct.pack(">HH", sport, dport)


def mode_stream(mode, sip, dip, sport, dport):
	if mode.endswith("_swap"):
		return stream_swapped_symmetric(sip, dip, sport, dport)
	if mode.endswith("_xor"):
		return stream_xor_symmetric(sip, dip, sport, dport)
	return stream4(sip, dip, sport, dport)


def parse_key_hex(s):
	"""Parse a key given as a hex string with arbitrary : or space separators."""
	hexs = re.sub(r"[^0-9a-fA-F]", "", s)
	if len(hexs) == 0 or len(hexs) % 2:
		raise ValueError("key hex must contain an even number of hex digits")
	return bytes.fromhex(hexs)


def parse_ethtool_x(text):
	"""Parse `ethtool -x <iface>` output.

	Returns (key, indir, toeplitz_on, symmetric): key is the dumped 40-byte
	key (or None), indir the table in printed order, and the last two are
	None or bools for the reported hash-function state.  Handles
	'RSS hash key:', 'Key:', 'Key *default*:' headers and multi-line hex.
	"""
	lines = text.splitlines()
	indir = []
	for i, ln in enumerate(lines):
		if "indirection table" in ln.lower():
			j = i + 1
			while j < len(lines):
				m = re.match(r"^\s*\d+:\s+((?:\d+\s*)+)$", lines[j])
				if not m:
					break
				indir.extend(int(t) for t in m.group(1).split())
				j += 1
			break
	key = None
	for i, ln in enumerate(lines):
		if not (re.search(r"(?i)hash key", ln) or
				(re.match(r"\s*key\b", ln, re.I) and ":" in ln)):
			continue
		toks = [re.sub(r"\*[^*]*\*", "", ln.split(":", 1)[1])]
		j = i + 1
		while j < len(lines):
			# Continuation lines: only hex byte pairs and separators.
			if re.search(r"[0-9a-fA-F]{2}", lines[j]) and \
					re.fullmatch(r"[\s:,0-9a-fA-F]+", lines[j]):
				toks.append(lines[j])
				j += 1
			else:
				break
		hexs = re.sub(r"[^0-9a-fA-F]", "", " ".join(toks))
		if hexs:
			key = bytes.fromhex(hexs)
			break
	toeplitz_on = None
	m = re.search(r"(?i)toeplitz\s*:\s*(on|off)", text)
	if m:
		toeplitz_on = (m.group(1).lower() == "on")
	symmetric = None
	m = re.search(r"(?i)symmetric[^a-z]*(on|off)", text)
	if m:
		symmetric = (m.group(1).lower() == "on")
	return key, indir, toeplitz_on, symmetric


def queue_for(hashval, indir):
	if not indir:
		return None
	return indir[hashval % len(indir)]


def predict_one(indir, key, mode, sip, dip, sport, dport):
	"""(hash, queue) under one named prediction mode."""
	data = mode_stream(mode, sip, dip, sport, dport)
	k = key[::-1] if mode.startswith("rev") else key
	h = toeplitz(k, data)
	return h, queue_for(h, indir)


def selftest():
	ok = True
	key = bytes.fromhex(DPDK_KEY)
	print("toeplitz selftest: 82599 RSS Verification Suite vectors")
	print("  (DPDK app/test/test_thash.c, key default_rss_key[])")
	for src, dst, sport, dport, l3, l4 in V4_VECTORS:
		got_l3 = toeplitz(key, stream_l3(src, dst))
		got_l4 = toeplitz(key, stream4(src, dst, sport, dport))
		good = (got_l3 == l3) and (got_l4 == l4)
		print("  %-15s:%-5u -> %-15s:%-6u l3 %08x l4 %08x  %s"
			  % (src, sport, dst, dport, got_l3, got_l4,
				 "OK" if good else "MISMATCH want l3 %08x l4 %08x" % (l3, l4)))
		ok = ok and good
	# Construction self-consistency checks.
	key2 = bytes.fromhex(DPDK_KEY)
	sw1 = toeplitz(key2, stream_swapped_symmetric("10.0.0.1", "10.0.0.2", 1000, 2000))
	sw2 = toeplitz(key2, stream_swapped_symmetric("10.0.0.2", "10.0.0.1", 2000, 1000))
	x1 = toeplitz(key2, stream_xor_symmetric("10.0.0.1", "10.0.0.2", 1000, 2000))
	x2 = toeplitz(key2, stream_xor_symmetric("10.0.0.2", "10.0.0.1", 1000, 2000))
	a = toeplitz(key2, stream4("10.0.0.1", "10.10.1.1", 40000, 5000))
	b = toeplitz(key2, stream4("10.0.0.1", "10.10.1.1", 40001, 5000))
	c = toeplitz(key2[::-1], stream4("10.0.0.1", "10.10.1.1", 40000, 5000))
	checks = [
		("swapped-symmetric direction invariance", sw1 == sw2),
		("xor-fold direction invariance", x1 == x2),
		("tuple sensitivity (sport change moves hash)", a != b),
		("key byte order matters", c != a),
	]
	for name, good in checks:
		print("  %-40s %s" % (name + ":", "OK" if good else "FAIL"))
		ok = ok and bool(good)
	print("selftest: %s" % ("PASS" if ok else "FAIL"))
	return 0 if ok else 1


def main():
	ap = argparse.ArgumentParser(
		description="reference Toeplitz RSS calculator (predicts mlx5 RX queue)")
	ap.add_argument("--ethtool", metavar="FILE",
					help="capture of `ethtool -x <iface>`; parses key + indir")
	ap.add_argument("--key",
					help="RSS key as a hex string (overrides --ethtool)")
	ap.add_argument("--indir", metavar="\"Q0 Q1 ...\"",
					help="indirection table entries in printed order")
	ap.add_argument("--indir-size", type=int,
					help="build uniform indir table 0..N-1 (power of two)")
	ap.add_argument("--key-order", choices=("fwd", "rev"), default="fwd",
					help="key byte order as consumed by the NIC "
						 "(default fwd: use the ethtool dump as printed)")
	ap.add_argument("--sip", help="source IPv4 address")
	ap.add_argument("--dip", help="destination IPv4 address")
	ap.add_argument("--sport", type=int, help="source L4 port")
	ap.add_argument("--dport", type=int, help="destination L4 port")
	ap.add_argument("--tuple-file", metavar="FILE",
					help="batch mode: lines of 'sip sport dport' "
						 "(dip from --dip); emits 'sport dport hash queue'")
	ap.add_argument("--all-modes", action="store_true",
					help="with --tuple-file: emit queues under all six "
						 "(key-order x canonicalization) prediction modes")
	ap.add_argument("--symmetric", action="store_true",
					help="predict with the best-effort XOR-fold symmetric "
						 "canonicalization instead of the plain 4-tuple")
	ap.add_argument("--selftest", action="store_true",
					help="verify against the 82599 verification vectors and exit")
	args = ap.parse_args()
	if args.selftest:
		sys.exit(selftest())

	indir = []
	if args.indir:
		indir = [int(t) for t in args.indir.split()]
	elif args.indir_size:
		n = args.indir_size
		if n & (n - 1):
			die("--indir-size must be a power of two")
		indir = list(range(n))
	if args.ethtool:
		with open(args.ethtool) as f:
			key, indir, toe_on, sym = parse_ethtool_x(f.read())
		if toe_on is False:
			print("toeplitz.py: note: dump reports toeplitz: off; "
				  "predictions will not match", file=sys.stderr)
		if sym:
			print("toeplitz.py: note: dump reports symmetric hashing (%s); "
				  "use --all-modes calibration or disable it (see README)"
				  % ("on" if sym else "off"), file=sys.stderr)
		if key is None:
			die("no hash key found in %s" % args.ethtool)
	if args.key:
		key = parse_key_hex(args.key)
	if key is None:
		die("no key: pass --ethtool FILE or --key HEX")
	if args.key_order == "rev":
		key = key[::-1]
	if len(key) != 40:
		print("toeplitz.py: warning: key is %d bytes; RSS keys are 40"
			  % len(key), file=sys.stderr)

	if args.all_modes:
		if not (args.dip and args.tuple_file):
			die("--all-modes needs --tuple-file and --dip")
		tuples = []
		for sip, sport, dport in iter_tuples(args.tuple_file):
			tuples.append((sip, args.dip, sport, dport))
		print("# queue per mode; mode order: " + " ".join(MODES))
		print("# indir_size %d key_len %d" % (len(indir), len(key)))
		for sip, dip, sport, dport in tuples:
			qs = []
			for m in MODES:
				k = key[::-1] if m.startswith("rev") else key
				h = toeplitz(k, mode_stream(m, sip, dip, sport, dport))
				q = queue_for(h, indir)
				qs.append("none" if q is None else str(q))
			print("%u %u %s" % (sport, dport, " ".join(qs)))
		return 0
	if args.tuple_file:
		if not args.dip:
			die("--tuple-file needs --dip")
		mode = "fwd_xor" if args.symmetric else "fwd"
		for sip, sport, dport in iter_tuples(args.tuple_file):
			h, q = predict_one(indir, key, mode, sip, args.dip, sport, dport)
			if q is None:
				print("hash=0x%08x queue=none" % h)
			else:
				print("hash=0x%08x queue=%d" % (h, q))
		return 0
	if not (args.sip and args.dip and args.sport is not None
			and args.dport is not None):
		die("need --sip --dip --sport --dport (or --tuple-file/--all-modes)")
	mode = "fwd_xor" if args.symmetric else "fwd"
	h, q = predict_one(indir, key, mode, args.sip, args.dip, args.sport,
					   args.dport)
	if q is None:
		print("hash=0x%08x queue=none" % h)
	else:
		print("hash=0x%08x queue=%d" % (h, q))
	return 0


def iter_tuples(path):
	with open(path) as f:
		for ln in f:
			flds = ln.split()
			if not flds or flds[0].startswith("#"):
				continue
			if len(flds) != 3:
				raise ValueError("tuple line %r: want 'sip sport dport'" % ln)
			yield flds[0], int(flds[1]), int(flds[2])


def die(msg):
	sys.stderr.write("toeplitz.py: %s\n" % msg)
	sys.exit(1)


if __name__ == "__main__":
	sys.exit(main())
