## e2e — CT-12 / Comptime §2.6: "a guard that fails during comptime evaluation is a LOCATED
## compile-time diagnostic at the operation's site … never deferred into the emitted program".
##
## `K : u64 = <u64 MAX> + 1` used to build GREEN and die with a bare SIGILL only when a run-time path
## reached `K` (and on a path never taken, die never) — the implementation fork CT-12 closes. The
## compiler had already evaluated the operation and already knew the answer was unrepresentable.
## Located at the arithmetic (line 8).
K : u64 = 18446744073709551615 + 1

main := fn() -> i64 {
  return i64(K)
}
