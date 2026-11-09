## #1397 — `==` / `!=` with a call to a GENERIC fn whose declared return is its type parameter
## (`id(T, v) -> T`), at a multi-word enum, struct or `Option(u64)`. By Stdlib appendix §2.6 `==` is the
## structural `eq`, and by Comptime §5.5 two enum values are equal exactly when they are the same variant
## with equal payloads. Covered: the call against a constructor, a local and another generic call; both
## orders; `==` and `!=`; an enum, a struct and an `Option(u64)` instance; the call as a by-reference
## argument. Exit 42 = every answer right; 11..27 name the first wrong one. NON-VACUOUS: see the PR (the
## parent refuses the first comparison, and generic call against generic call compared word 0).

E := enum { U, A(u64), T(u8, u64) }
P := struct { x : u64, y : u64 }
id := fn(T : type, v : T) -> T { v }
same := fn(a : E, b : E) -> bool { a == b }

main := fn() -> u64 {
  x := E.T(4, 5)
  if not (id(E, x) == E.T(4, 5)) { return 11 }
  if id(E, x) != E.T(4, 5) { return 12 }
  if not (E.T(4, 5) == id(E, x)) { return 13 }
  if id(E, x) == E.T(4, 6) { return 14 }
  if id(E, x) == E.U { return 15 }
  y := E.T(4, 5)
  if not (id(E, x) == y) { return 16 }
  if y != id(E, x) { return 17 }
  w := E.T(4, 6)
  if id(E, x) == id(E, w) { return 18 }
  if not (id(E, x) == id(E, y)) { return 19 }
  if not same(id(E, x), E.T(4, 5)) { return 20 }
  if same(id(E, x), E.T(4, 6)) { return 21 }
  p := P(x = 1, y = 2)
  if not (id(P, p) == P(x = 1, y = 2)) { return 22 }
  if id(P, p) == P(x = 1, y = 3) { return 23 }
  q := P(x = 1, y = 3)
  if id(P, p) == id(P, q) { return 24 }
  o : Option(u64) = Option.Some(7)
  if not (id(Option(u64), o) == Option.Some(7)) { return 25 }
  if id(Option(u64), o) == Option.Some(8) { return 26 }
  if id(Option(u64), o) == Option.None { return 27 }
  42
}
## expect: run 42
