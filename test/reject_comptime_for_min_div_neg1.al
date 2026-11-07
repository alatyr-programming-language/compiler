## e2e (#1233) — a checked `MIN / -1` in a `comptime for` range bound is a LOCATED diagnostic.
##
## Comptime §2.6 (spec v1.6.0): a guard that fails during comptime evaluation is rejected where it is
## written, "never deferred into the emitted program", and `MIN / -1` is a member of the checked-overflow
## set (Concurrency §6.1). The bound is folded by `lower_layout::ct_range_guard` / `ct_range_perform`;
## before the guard neither `/` nor `%` was checked there at all, so the fold ran the HOST's `idiv`.
##
## Measured on the parent (native x86_64, omen, `seed/alatyr`): the compiler died with SIGFPE, rc 136,
## no message and no location — a crash, not a diagnostic. Here x86 refuses at the divisor.
main := fn() -> u64 {
  mut total : u64 = 0
  comptime for i in 0 .. ((0 - 9223372036854775807 - 1) / (0 - 1)) { total = total + 1 }
  if total != 0 { return 1 }
  return 42
}
## expect: reject "divides the minimum value of its type by -1" "at line 12 in "
