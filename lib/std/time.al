## std::time — wall-clock and monotonic time via `clock_gettime(2)` (Linux x86_64 syscall 228).
##
## `clock_gettime(clk_id, *timespec)` writes a `{sec, nsec}` pair (two 8-byte words) to the pointer.
## Taking `ptr` of a bare local is not a place, so the timespec buffer is an ARENA slot (its raw
## address IS a place — the established std idiom, mirroring `std::process`'s wait4 status word). The
## clock ids: CLOCK_REALTIME = 0 (wall clock, subject to NTP steps), CLOCK_MONOTONIC = 1 (never steps
## backward — the one to use for measuring elapsed intervals).

sys_clock_gettime := @abi(syscall) fn(num : usize, clk : usize, ts : usize) -> isize

## A point in time as the kernel reports it: whole seconds + nanoseconds within the second (§ posix
## `struct timespec`). Both `i64` so a difference (which can be negative for a REALTIME step) is signed.
pub Timespec := struct { sec : i64, nsec : i64 }

## Read clock `clk` into a `Timespec`. A syscall failure yields `{0, 0}` (the caller treats a zero
## timespec as "unavailable"); on Linux/x86_64 `clock_gettime` for a supported clock does not fail.
read_clock := fn(a : ptr(mut Arena), clk : usize) -> Timespec {
  ## a 2-word (16-byte) arena slot for the {sec, nsec} the kernel writes.
  rs := allocate(deref(a), i64, 2, 8)
  mut tidx : usize = 0
  match rs {
    Result::Ok(h) => { tidx = h.idx }
    Result::Err(e) => { return Timespec(sec = 0, nsec = 0) }
  }
  aa := deref(a)
  tbase := get(i64, aa, Handle(i64)(idx = tidx))
  tp := unchecked bitcast(usize, tbase)
  secp := unchecked bitcast(ptr(mut i64), tp)
  nsecp := unchecked bitcast(ptr(mut i64), tp + 8)
  deref(secp) = 0
  deref(nsecp) = 0
  r := unchecked sys_clock_gettime(228, clk, tp)
  if r < 0 { return Timespec(sec = 0, nsec = 0) }
  Timespec(sec = deref(secp), nsec = deref(nsecp))
}

## The current MONOTONIC time (CLOCK_MONOTONIC) — never steps backward; use it to measure elapsed
## intervals (`diff_nanos(later, earlier)`).
pub now_monotonic := fn(a : ptr(mut Arena)) -> Timespec { read_clock(a, 1) }

## The current WALL-CLOCK time (CLOCK_REALTIME) — seconds since the Unix epoch (1970-01-01 UTC), NTP-
## adjustable (may jump). Use it for timestamps, not for measuring durations.
pub now_realtime := fn(a : ptr(mut Arena)) -> Timespec { read_clock(a, 0) }

## The timespec as a whole count of nanoseconds (`sec * 1e9 + nsec`). Checked arithmetic: a REALTIME
## value (~1.7e18 ns) stays well within i64's ~9.2e18 range.
pub to_nanos := fn(t : Timespec) -> i64 { t.sec * 1000000000 + t.nsec }

## The timespec as a whole count of milliseconds (nanoseconds / 1e6).
pub to_millis := fn(t : Timespec) -> i64 { to_nanos(t) / 1000000 }

## Elapsed nanoseconds from `earlier` to `later` (`later - earlier`); negative if `earlier` is after
## `later` (possible for two REALTIME reads across an NTP step, never for two MONOTONIC reads).
pub diff_nanos := fn(later : Timespec, earlier : Timespec) -> i64 {
  a_ns := to_nanos(later)
  b_ns := to_nanos(earlier)
  a_ns - b_ns
}
