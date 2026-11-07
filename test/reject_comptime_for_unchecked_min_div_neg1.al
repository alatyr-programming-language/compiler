## e2e (#1233) — `MIN / -1` in a `comptime for` range bound stays a diagnostic INSIDE `unchecked`.
##
## Comptime §2.6 (spec v1.6.0), the clause that makes this case different from every other guard in the
## family: "Inside an `unchecked` scope (CT-11) the evaluator drops the guards exactly as run time does,
## with one difference forced by there being no machine: an operation whose unchecked behaviour is
## *hardware-defined* rather than *defined* — division by zero, an over-width shift, **`MIN / -1`** and
## **`MIN % -1`** (Concurrency §6.2) — remains a **diagnostic** at comptime, because the evaluator has
## no hardware behaviour to reproduce and I11 forbids inventing one." So `unchecked` does NOT release
## this bound, while it DOES release the two's-complement wrap of `+ - *` in the same scope.
##
## Measured on the parent (native x86_64, `seed/alatyr`): SIGFPE, rc 136, no message, no location.
main := fn() -> u64 {
  mut total : u64 = 0
  comptime for i in 0 .. unchecked ((0 - 9223372036854775807 - 1) / (0 - 1)) { total = total + 1 }
  if total != 0 { return 1 }
  return 42
}
## expect: reject "divides the minimum value of its type by -1" "at line 14 in "
