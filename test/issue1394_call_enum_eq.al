## #1394 — `==` / `!=` with a CALL operand that returns a multi-word struct or enum by value (Stdlib
## appendix §2.6: `==` is the structural `eq`; Comptime §5.5: two enum values are equal exactly when
## they are the same variant with equal payloads). The bare-comparison routing classified a local and a
## constructor as aggregates but not a call, so `mk(2) == E.A(7)` compared the returned tag in `%rax`
## with the `$0` a multi-word constructor materializes as in a scalar position, and never built the
## constructor. Covered: payload none / scalar / two words / struct / `str`; `==` and `!=`; the call on
## either side; call against call and against a local; a struct-returning call; a wide (hidden result
## pointer) struct and enum return; a call through a fn value; call against call in a function that
## builds nothing wider (`calls_only_*`). Exit 42 = every answer right; 10..39 and 43..44 name the first
## wrong one; a trap ends with a signal. NON-VACUOUS: on the parent `ea6651db` (x86_64) this program
## exits 11, and on #1400's first head `927f3981` it exits 43 (the pool blocks of `mk(1) == mk(1)` were
## one word wide there, so the second result overwrote the first).

P := struct { x : u64, y : u64 }
W := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64 }
E := enum { U, A(u64), T(u8, u64), S(P), N(str) }
V := enum { Lo, Hi(W) }

mk := fn(k : u64) -> E {
  if k == 1 { return E.T(4, 5) }
  if k == 2 { return E.A(7) }
  if k == 3 { return E.S(P(x = 1, y = 2)) }
  if k == 4 { return E.N("abc") }
  E.U
}
mp := fn(y : u64) -> P { P(x = 3, y = y) }
mw := fn(h : u64) -> W { W(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = h) }
mv := fn(h : u64) -> V { V.Hi(mw(h)) }
## Call against call and nothing else: the agg-temp pool's block width comes from this function alone,
## so it must come from the calls' own result width (`main` below builds the 8-word `W`, which would
## widen every block and hide a too-narrow one). ONE comparison per function: with four call-against-call
## comparisons in one function, `927f3981` answered all four right (measured), so that shape proves nothing.
calls_only_eq := fn() -> bool { mk(1) == mk(1) }
calls_only_ne := fn() -> bool { mk(1) != mk(1) }

main := fn() -> u64 {
  if not calls_only_eq() { return 43 }
  if calls_only_ne() { return 44 }
  ## a scalar payload, the issue's first row
  if not (mk(2) == E.A(7)) { return 11 }
  if mk(2) == E.A(8) { return 12 }
  if mk(2) != E.A(7) { return 13 }
  if not (mk(2) != E.A(8)) { return 14 }
  ## a two-word payload, call on either side
  if not (mk(1) == E.T(4, 5)) { return 15 }
  if mk(1) != E.T(4, 5) { return 16 }
  if not (E.T(4, 5) == mk(1)) { return 17 }
  if mk(1) == E.T(4, 6) { return 18 }
  if E.T(3, 5) == mk(1) { return 19 }
  ## no payload, and a variant mismatch
  if not (mk(0) == E.U) { return 20 }
  if mk(0) != E.U { return 21 }
  if mk(2) == E.U { return 22 }
  if E.A(0) == mk(0) { return 23 }
  ## a struct payload and a str payload
  if not (mk(3) == E.S(P(x = 1, y = 2))) { return 24 }
  if mk(3) == E.S(P(x = 1, y = 3)) { return 25 }
  if not (mk(4) == E.N("abc")) { return 26 }
  if mk(4) == E.N("abd") { return 27 }
  ## call against call, and against a local
  if not (mk(1) == mk(1)) { return 28 }
  if mk(1) == mk(2) { return 29 }
  x := mk(1)
  if not (x == mk(1)) { return 30 }
  if mk(2) == x { return 31 }
  ## a struct-returning call
  if not (mp(9) == P(x = 3, y = 9)) { return 32 }
  if P(x = 3, y = 8) == mp(9) { return 33 }
  ## a wide struct and a wide enum, returned through a hidden result pointer
  if not (mw(8) == W(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8)) { return 34 }
  if mw(8) == W(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 9) { return 35 }
  if not (mv(8) == V.Hi(mw(8))) { return 36 }
  if mv(8) == V.Hi(mw(9)) { return 37 }
  ## a call through a fn value
  f := mk
  if not (f(2) == E.A(7)) { return 38 }
  if f(2) == E.A(9) { return 39 }
  42
}
## expect: run 42
