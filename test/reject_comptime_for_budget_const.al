## e2e (#1499) — a `comptime for` over a module-const bound one past the unroll budget is a LOCATED
## refusal. The literal-only spelling was already refused by the checker; a const bound reached the
## lower's budget test, which aborted the compiler with an internal message and no source location.
##
## Comptime §2.2 (spec v1.8.0): exceeding the step budget is a compile-time failure, never a silent
## partial result. Measured on the parent (`f9ca474d`, native x86_64, omen): x86_64 exited 1 with
## `selfhost: comptime-for range exceeds the unroll budget (100000)` and no line; the twins compiled
## it and trapped (133 / 133 / 134). Here x86_64 refuses at the bound; the twins trap until #1232.
N : u64 = 100001

main := fn() -> u64 {
  mut a : u64 = 0
  comptime for i in 0 .. N { a = a + 1 }
  return a + 7
}
## expect: reject "budget exhausted" "never a silent partial result. at line 13 in "
