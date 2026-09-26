#!/bin/bash
# p1/persist.sh -- DR-007 Task A: PERSIST arms per the frozen spec
# (specs/p1-PERSIST.md + Amendment A). 7 arms x 10 rounds, one of each
# per round; the A7/A8 pair alternates its position across rounds; A0
# rotates. rxrecover.sh after every dead cell (halt+alert on failure).
# Smoke: one A8 cell first (the spec's discipline). Commit before running.
set -u
IFACE=enp195s0np0
exec >> /root/p1/persist.log 2>&1
echo "PERSIST START $(date -u +%FT%TZ) args=$*"

set_flag() { # on|off -- rx_striding_rq; skip when already there (no
            # needless recreation), preflight only after a real change
            # (protocol: after every ring/flag/channel change)
  local to=$1
  local cur=$(ethtool --show-priv-flags $IFACE | awk -F': ' '/rx_striding_rq/{print $2}')
  if [ "$cur" = "$to" ]; then
    echo "flag already $to (no change)"
    return 0
  fi
  ethtool --set-priv-flags $IFACE rx_striding_rq "$to"
  sleep 2
  bash /root/p1/preflight.sh || { echo "PREFLIGHT FAIL after flag=$1"; exit 1; }
}

run_cell() { # arm idx wire threaded core rate quiet
  local A=$1 I=$2 W=$3 TH=$4 CO=$5 RA=$6 Q=$7
  local D=/root/p1/metastab/M1-p-$A-$I
  echo "== $A cell $I $(date -u +%FT%TZ)"
  bash /root/p1/metastab.sh M 10 "p-$A-$I" "$W" "$TH" "$CO" "$RA" "$Q"
  V=$(grep -E "PROBE-(DEAD|OK)" "$D/cell.env" 2>/dev/null | tail -1)
  echo "== $A cell $I verdict: $V $(date -u +%FT%TZ)"
  case "$V" in
    *PROBE-DEAD*)
      if ! bash /root/p1/rxrecover.sh "/root/p1/rxrecover-p-$A-$I.log"; then
        echo "ALERT: recovery FAILED after $A cell $I -- halting the batch"
        touch /root/p1/PERSIST-RECOVERY-FAIL
        exit 3
      fi ;;
  esac
}

round() { # r
  local r=$1
  local S1=S7 S2=S8
  [ $((r % 2)) = 0 ] && { S1=S8; S2=S7; }
  # A0 rotates through positions 1..7 across rounds
  case $(( (r - 1) % 7 )) in
    0) ORDER="A0 A1 A4 A5 A6 $S1 $S2" ;;
    1) ORDER="A1 A0 A4 A5 A6 $S1 $S2" ;;
    2) ORDER="A1 A4 A0 A5 A6 $S1 $S2" ;;
    3) ORDER="A1 A4 A5 A0 A6 $S1 $S2" ;;
    4) ORDER="A1 A4 A5 A6 A0 $S1 $S2" ;;
    5) ORDER="A1 A4 A5 A6 $S1 A0 $S2" ;;
    6) ORDER="A1 A4 A5 A6 $S1 $S2 A0" ;;
  esac
  echo "ROUND $r order: $ORDER $(date -u +%FT%TZ)"
  for A in $ORDER; do
    case "$A" in
      A0) set_flag on; run_cell A0 "$r" unpin 1 8 158000 300 ;;
      A1) set_flag on; run_cell A1 "$r" unpin 1 8 158000 20 ;;
      A4) set_flag on; run_cell A4 "$r" unpin 0 8 158000 20 ;;
      A5) set_flag on; run_cell A5 "$r" unpin 0 16 158000 20 ;;
      A6) set_flag on; run_cell A6 "$r" unpin 1 8 105000 20 ;;
      S7) set_flag on;  run_cell A7 "$r" unpin 1 8 158000 20 ;;
      S8) set_flag off; run_cell A8 "$r" unpin 1 8 158000 20 ;;
    esac
  done
}

# ---- smoke: one A8 cell (the spec's discipline) ----
if [ "${1:-}" = smoke ]; then
  set_flag off
  run_cell A8 0 unpin 1 8 158000 20
  set_flag on
  bash /root/p1/preflight.sh
  echo "PERSIST SMOKE DONE $(date -u +%FT%TZ)"
  exit 0
fi

for r in 1 2 3 4 5 6 7 8 9 10; do round "$r"; done
# restore platform defaults
ethtool -G $IFACE rx 1024
ethtool --set-priv-flags $IFACE rx_striding_rq on
bash /root/p1/preflight.sh
echo "PERSIST DONE $(date -u +%FT%TZ)"
touch /root/p1/PERSIST-DONE
