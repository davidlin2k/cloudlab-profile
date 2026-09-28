# Addendum to specs/p1-REARM.md and p1-WATCHDOG.md (phenotype-B trigger)

Pre-registered 2026-09-28, after the frozen specs (commit a9e9430) but
BEFORE any further r6615 run, per the promise in the T1F session.
Supersedes the trigger wording below ONLY where stated; everything
else in the frozen specs stands.  Facts only.

## 1. The gate bug found during T1F bring-up

The rearm hook as built would not fire unless the watched CQ held a
READY completion at the moment of the check.  That predicate is blind
to exactly the case the hook exists for: the AN-003 phenotype has
ready work stranded with the poller NOT running (state 0x18 = LISTED |
MISSED, x59,671 samples, pkt counter frozen at 350,720, ev frozen at
12,156, out_of_buffer +36,000,000, wedge >= 15 min).  Requiring the
poller to have made progress before the hook can act inverts the
condition.  Additionally the module param used a plain module_param,
so the predicate could not be widened at runtime; it is now param_cb.

## 2. The widened trigger (replaces the p1-REARM trigger wording)

FIRE the hook when ALL of (phenotype B):

  - the EQ reports MISSED (0x18 observed on the EQ's state), and
  - the poller is idle (no napi kthread runnable on the queue's CPU),
  - the queue's packet counter has been frozen >= 50 ms.

On fire, take action (b) ONLY: `napi_schedule`.  The re-arm doorbell
(action (a)) is NOT taken for phenotype B: the doorbell is the
device-side remedy for the T1a class (EQ empty + CQ ready + arm armed
-- device-side silence), and taking it here would destroy the
phenotype's evidence.  The decision-table rows of the frozen specs
keep their mapping: T1a-class -> (a); AN-003/phenotype-B class -> (b).

## 3. Watchdog pre-registration (unchanged, restated for one page)

pin46 arm, n=8, T = 100 ms; works = gap <= 2T every cell AND no
goodput loss -> upstream RFC.

## 4. Build status at the time of this addendum

clnode323 build #7 (net-next 7.3.0-rc4+ base 014d795c7) carries the
param_cb + widened predicate (mlx5_core.ko 187,665,953 B).  T1F-1 ran
healthy (0 strands); T1F-2..8 aborted on a sticky wedge; T1F-LIVE
captured the AN-003 phenotype (x59,671 samples, state 0x18).  The
live fire of the widened hook is pending: clnode323 is down (hang #2)
awaiting a console action.
