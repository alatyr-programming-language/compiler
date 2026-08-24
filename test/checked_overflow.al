## CG-13 / Concurrency §6.1: a checked routed scalar `*` still fails through the compiler's direct
## inline trap. `std::io` injects `base::num`, so this is the routed path; the operator body carries no
## panic guard and the operation-site guard emits `ud2` (exit 132), exactly like the freestanding
## built-in path. x86_64-only: scalar operator routing is x86_64-gated. Companion `unchecked` arithmetic
## drops the operation-site guard and wraps.
main := fn() -> u64 {
  z := std::io::print("")
  a : u64 = 9999999999
  b : u64 = 9999999999
  return a * b + u64(z)
}
