## e2e (#684) — a zero divisor in a `comptime for` range bound is a LOCATED compile-time diagnostic.
##
## Comptime §2.6 (spec v1.6.0): a guard that fails during comptime evaluation is a located
## compile-time diagnostic at the operation's site, and division by zero is named in that set.
##
## Measured on the parent (`2cf60b45`, native x86_64): the x86 compiler died with SIGFPE (rc 136)
## and no message; aarch64, riscv64 and wasm emitted clean, and the program unrolled zero times and
## exited 42. Here x86 refuses at the divisor's line, and the twins trap rather than loop zero times.
main := fn() -> u64 {
  mut total : u64 = 0
  comptime for i in 0 .. 4 / 0 { total = total + 1 }
  if total != 0 { return 1 }
  return 42
}
