## #638 (found by the #602 research, and closed by the same normalisation) — a `comptime for` over
## a range with a NEGATIVE bound silently unrolled the wrong iteration set.
##
## `ct_bound_fold` and its three non-x86 twins return a sentinel to mean "I could not fold this
## bound", and the callers cannot tell a declined bound from a computed one. A written negative
## literal was `Unchecked(Bin(17, Num(0), Num(2)))`, which every one of them declined, so the lower
## bound silently became 0. Measured on the parent, THIS program returns 1 on all four backends:
## `comptime for i in -2..2` iterated 0 and 1 — two of the four iterations the range names — and
## the program still compiled clean and exited 0.
##
## The sentinel itself is not fixed here and does not need to be for this shape: under the
## normalisation the bound folds, so the decline never happens. A DECLINED bound is still
## indistinguishable from 0 for every other expression form, which is why #638 stays open on that
## residual — in particular `comptime for j in 0 - 2..2`, the same range written as a binary
## subtraction, still unrolls 0 and 1 on the three non-x86 backends. It is deliberately NOT
## asserted here: it needs constant folding of `Bin(op, Num, Num)` in those three range-bound
## resolvers, which is #590's third row, and a row asserting today's answer would freeze a defect.
##
## The three non-x86 unrolls needed one repair to reach this at all. Their counter is compared with
## a SIGNED `<` but its increment took the self-host lower's UNSIGNED carry guard, so at k = -1 the
## increment carried and each emitter died on its own `ud2` with no diagnostic — a defect that no
## program could reach until this bound could be negative.
main := fn() -> u64 {
  mut s : i64 = 0
  mut n : i64 = 0
  comptime for i in -2..2 {
    s = s + i
    n = n + 1
  }
  mut lo : i64 = 0
  comptime for k in -1..0 {
    lo = lo + k
  }
  if n != 4 { return 1 }
  if s != 0 - 2 { return 2 }
  if lo != 0 - 1 { return 3 }
  return 42
}
