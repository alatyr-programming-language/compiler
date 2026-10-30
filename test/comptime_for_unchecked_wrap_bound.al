## e2e (#1234) — control for the range-bound overflow diagnostic: inside `unchecked` the wrap is
## DEFINED (Comptime §2.6, spec v1.6.0: the evaluator drops the overflow guard as run time does), so the
## bound folds to the wrapped value, and a checked bound that fits is unaffected.
##
## Expected: 42 on all four backends. `unchecked (U + 2)` wraps to 1 (one iteration),
## `unchecked (S + 1)` wraps to MIN (zero iterations), and `N * 2 - 1` is 5. A const's own initializer
## is judged in its own mode: `W`'s `unchecked` reaches no further than `W`.
## Measured on the parent (#1229's head `833d9285`, native x86_64): 42 on all four. This file guards
## against the fix reaching inside `unchecked`.
U : u64 = 18446744073709551615
S : i64 = 9223372036854775807
N : i64 = 3
W : u64 = unchecked (U + 3)

main := fn() -> u64 {
  mut a : u64 = 0
  comptime for i in 0 .. unchecked (U + 2) { a = a + 1 }
  if a != 1 { return 1 }
  mut b : u64 = 0
  comptime for i in 0 .. unchecked (S + 1) { b = b + 1 }
  if b != 0 { return 2 }
  mut c : u64 = 0
  comptime for i in 0 .. N * 2 - 1 { c = c + 1 }
  if c != 5 { return 3 }
  mut d : u64 = 0
  comptime for i in 0 .. W + 1 { d = d + 1 }
  if d != 3 { return 4 }
  return 42
}
