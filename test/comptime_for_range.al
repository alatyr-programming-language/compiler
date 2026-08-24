## e2e (§3 — a COMPTIME-FOR over a numeric RANGE, `comptime for i in lo .. hi { body }`). Unlike the
## typeinfo `comptime for` (over a type's members), this iterates a compile-time integer range and is
## UNROLLED at compile time: for each constant `k` in `[lo, hi)` the body is emitted with the loop var
## bound to `k` (a scalar local set to the immediate). Previously the parser consumed the range form as
## a silent NO-OP, so the body never ran (wrong results). `src/`+`lib/` use the typeinfo comptime-for
## and runtime `for`, not a range comptime-for, so this stays fixpoint-neutral.
N := 6

main := fn() -> u64 {
  mut s : u64 = 0
  comptime for i in 0 .. 6 { s = s + i }        ## unrolled: 0+1+2+3+4+5 = 15
  mut t : u64 = 0
  comptime for j in 0 .. N { t = t + 1 }         ## const bound N=6 → 6 iterations → t = 6
  mut u : u64 = 0
  comptime for k in 2 .. 5 { u = u + k }         ## 2+3+4 = 9
  ## 15 + 6 + 9 = 30; + 12 = 42
  s + t + u + 12
}
