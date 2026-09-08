## e2e — Issue #299's ACCEPT side, and the reason the refusal is not over-reach. Every Types §4.2
## brand class has an expressible explicit spelling, and all of them are here:
##   B1  a raw value into a brand         → `A(r)`
##   B1R a brand value into a raw sink    → `u64(a)`
##   B2  a sibling brand                  → `A(u64(b))`, through the block the two share (§5.4 gives
##                                          siblings no conversion of their own)
##   B3  a brand over another block       → `A(u64(u8(c)))`
##   B4  one operator over two brands     → `u64(a) + u64(b)`
## plus the two controls the refusal must NOT touch:
##   • WIDEN stays IMPLICIT. §4.3 makes widen the only implicit conversion class, so `wide : u64 = narrow`
##     for a `narrow : u32` must keep working; a brand-identity fence that reached it would be a
##     regression against the specification, not a stricter reading of it.
##   • the SAME brand remains self-consistent — `a2 : A = a`, `take_a(a)` and `a + a2`.
## Returns 42.
## RUNS to its value on x86_64 only. The three non-x86 backends implement a scalar core that does not
## lower a brand construction at all, so every brand-declaring program in this tree already traps
## loudly there: `test/accept_ann_brand_and_generic.al` is `run/12` on x86_64 and `run/133 · 133 · 134`
## on aarch64 · riscv64 · wasm in the committed manifest, measured on the PARENT compiler, and these
## rows are the same shape. That is a pre-existing backend-subset limit, not this refusal's doing —
## the four-backend claim this unit owes is that all four surfaces REFUSE an implicit crossing, and
## `test/reject_brand_sibling_sink.al` carries it as `compile/1` on every one of them.
A := brand(u64)
B := brand(u64)
C := brand(u8)

take_a := fn(x : A) -> u64 { u64(x) }
take_r := fn(x : u64) -> u64 { x }

main := fn() -> u64 {
  r : u64 = 3
  a : A = A(r)
  b : B = B(4)
  c : C = C(5)

  ## B1 / B1R — the two directions of a brand conversion, each written as §4.2 requires.
  if take_a(A(r)) != 3 { return 1 }
  if take_r(u64(a)) != 3 { return 2 }

  ## B2 / B3 — a sibling and a different block, routed through the shared representation.
  if take_a(A(u64(b))) != 4 { return 3 }
  if take_a(A(u64(u8(c)))) != 5 { return 4 }

  ## B4 — one operator over two brands, on the block they share.
  if u64(a) + u64(b) != 7 { return 5 }

  ## the SAME brand: assignment, argument and operator all stay accepted.
  a2 : A = a
  if take_a(a2) != 3 { return 6 }
  if u64(a + a2) != 6 { return 7 }

  ## WIDEN is still implicit (§4.3) — no brand anywhere near it.
  narrow : u32 = 9
  wide : u64 = narrow
  if wide != 9 { return 8 }

  return 42
}
