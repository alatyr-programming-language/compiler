## #1396 — `==` / `!=` with a FIELD read, an `if` expression or a `match` expression operand whose value
## is a multi-word enum or struct (Stdlib appendix §2.6: `==` is the structural `eq`; Comptime §5.5: two
## enum values are equal exactly when they are the same variant with equal payloads). The bare-comparison
## routing classified a local, a constructor and a concrete call as aggregates, but not these three, so
## `h.e == E.T(4, 5)` compared the field's word 0 with the `$0` a multi-word constructor materializes as
## in a scalar position. An `if`/`match` whose first branch is an enum-returning call was not even an
## aggregate VALUE: `y := if c { mk(1) } else { E.U }` bound the tag alone (rows 51-52), and the same
## `if` passed as an argument handed the tag over as a block pointer (row 53).
## Covered: the issue's four rows (11-14); an enum and a struct field; `==` and `!=`; the field on either
## side; field against field, against a local and against a call; a nested field; an `Option(u64)` field;
## a by-reference param base and a `deref(p)` base; `if` and `match` operands with call and literal
## branches, on either side, against a constructor, a field, a local and a call; the binding and the
## argument of the same shapes. Exit 42 = every answer right; 11..55 name the first wrong one; a trap
## ends with a signal. NON-VACUOUS: see the PR (the parent answers 11).

P := struct { x : u64, y : u64 }
E := enum { U, A(u64), T(u8, u64), S(P) }
H := struct { e : E, k : u64, p : P, o : Option(u64) }
O := struct { h : H, z : u64 }

mk := fn(k : u64) -> E {
  if k == 1 { return E.T(4, 5) }
  if k == 2 { return E.T(4, 6) }
  E.U
}
mp := fn(y : u64) -> P { P(x = 3, y = y) }
same := fn(a : E, b : E) -> bool { a == b }
## A by-reference struct param as the field's base: 0 = every answer right.
byref := fn(h : H) -> u64 {
  if not (h.e == E.T(4, 5)) { return 1 }
  if h.e != E.T(4, 5) { return 2 }
  if h.e == E.T(4, 6) { return 3 }
  0
}
## A `deref(p)` base: 0 = every answer right.
viaptr := fn(q : ptr(H)) -> u64 {
  if not (deref(q).e == E.T(4, 5)) { return 1 }
  if deref(q).e == E.T(4, 6) { return 2 }
  0
}

main := fn() -> u64 {
  mut h := H(e = E.T(4, 5), k = 1, p = P(x = 1, y = 2), o = Option.Some(3))
  g := H(e = E.T(4, 6), k = 1, p = P(x = 1, y = 2), o = Option.None)
  c := true
  n := false
  ## the issue's rows
  if not (h.e == E.T(4, 5)) { return 11 }
  if not (E.T(4, 5) == h.e) { return 12 }
  if not ((if c { mk(1) } else { E.U }) == E.T(4, 5)) { return 13 }
  if not ((match c { true => { mk(1) }, false => { E.U } }) == E.T(4, 5)) { return 14 }
  ## an enum field: equal tags with different payloads, `!=`
  if h.e == E.T(4, 6) { return 15 }
  if E.T(3, 5) == h.e { return 16 }
  if h.e != E.T(4, 5) { return 17 }
  if not (h.e != E.U) { return 18 }
  ## a struct field
  if not (h.p == P(x = 1, y = 2)) { return 19 }
  if h.p == P(x = 1, y = 3) { return 20 }
  if h.p == mp(2) { return 21 }
  ## field against field, against a local, against a call
  if h.e == g.e { return 22 }
  if not (h.p == g.p) { return 23 }
  x := E.T(4, 5)
  if not (h.e == x) { return 24 }
  if not (x == h.e) { return 25 }
  if not (h.e == mk(1)) { return 26 }
  if h.e == mk(2) { return 27 }
  ## a nested field
  o := O(h = h, z = 9)
  if not (o.h.e == E.T(4, 5)) { return 28 }
  if o.h.e == E.T(4, 6) { return 29 }
  if not (o.h.p == P(x = 1, y = 2)) { return 30 }
  ## an `Option(u64)` field
  if not (h.o == Option.Some(3)) { return 31 }
  if h.o == Option.Some(4) { return 32 }
  if h.o == Option.None { return 33 }
  if not (g.o == Option.None) { return 34 }
  ## a by-reference param base, a `deref(p)` base
  if byref(h) != 0 { return 35 }
  if viaptr(ptr(h)) != 0 { return 36 }
  ## `if` / `match` operands
  if (if c { mk(2) } else { E.U }) == E.T(4, 5) { return 37 }
  if not (E.T(4, 5) == (if c { mk(1) } else { E.U })) { return 38 }
  if not ((if n { E.U } else { mk(1) }) == E.T(4, 5)) { return 39 }
  if (if n { mk(1) } else { mk(2) }) != E.T(4, 6) { return 40 }
  if (match n { true => { mk(1) }, false => { E.U } }) != E.U { return 41 }
  if not ((if c { mp(2) } else { P(x = 0, y = 0) }) == P(x = 3, y = 2)) { return 43 }
  if not ((if c { E.T(4, 5) } else { E.U }) == h.e) { return 44 }
  if not ((if c { mk(1) } else { E.U }) == x) { return 45 }
  if (if c { mk(1) } else { E.U }) == mk(2) { return 46 }
  ## the binding and the argument of the same shapes
  y := if c { mk(1) } else { E.U }
  if not (y == E.T(4, 5)) { return 51 }
  z := match c { true => { mk(2) }, false => { E.U } }
  if z == E.T(4, 5) { return 52 }
  if not same(if c { mk(1) } else { E.U }, E.T(4, 5)) { return 53 }
  if same(match c { true => { mk(2) }, false => { E.U } }, E.T(4, 5)) { return 54 }
  42
}
## expect: run 42
