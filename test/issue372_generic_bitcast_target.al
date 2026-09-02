## e2e (a PARENTHESIZED generic INSTANCE is a bitcast TARGET). Types §3.4/§4.4 make `bitcast` the
## identity on the block at equal bit width, so reinterpreting a value into a generic aggregate
## instance must preserve THAT instance's layout. Before the fix the parenthesized target was erased
## whole: the local bound from it kept no aggregate type at all, so every field read ZERO — a
## clean-compiling wrong value. Every field is verified SEPARATELY, never through a sum, so a
## permuted or partially copied image is visible; the neighbouring values are non-zero and pairwise
## distinct for the same reason. Each failure carries its own code from 100 so the answer names the
## word that moved wrong. Success is 42; every failure code is distinct and below 126.
Box := fn(T : type) -> type { return struct { v : T } }
Pair := fn(T : type) -> type { return struct { x : T, y : T } }
Tri := fn(T : type) -> type { return struct { p : T, q : T, r : T } }
Opt := fn(T : type) -> type { return enum { Some(T), None } }
Alt := fn(T : type) -> type { return enum { Val(T), Nil } }
P := struct { a : u64, b : u64 }
W3 := struct { a : u64, b : u64, c : u64 }

main := fn() -> u64 {
  ## Width controls: every reinterpret below is equal-width by construction.
  if size(P) != size(Box(P)) { return 100 }
  if size(P) != size(Pair(u64)) { return 101 }
  if size(W3) != size(Tri(u64)) { return 102 }

  ## Control: ordinary generic CONSTRUCTION needs no bitcast and must stay correct.
  p0 := P(a = 7, b = 9)
  c := Box(P)(v = p0)
  if c.v.a != 7 { return 103 }
  if c.v.b != 9 { return 104 }

  p := P(a = 10, b = 32)

  ## An AGGREGATE type-arg: field `v : T` substitutes to the struct P, so `y.v.a` / `y.v.b` are a
  ## NESTED read through the instance's substituted layout — the shape that read zero.
  y := unchecked bitcast(Box(P), p)
  if y.v.a != 10 { return 105 }
  if y.v.b != 32 { return 106 }

  ## The checked spelling must agree with the unchecked one — verification mode is not a
  ## representation change.
  g := bitcast(Box(P), p)
  if g.v.a != 10 { return 107 }
  if g.v.b != 32 { return 108 }

  ## A SCALAR type-arg instance: two type-param fields, each verified on its own.
  q := unchecked bitcast(Pair(u64), p)
  if q.x != 10 { return 109 }
  if q.y != 32 { return 110 }

  ## THREE words, three distinct non-zero values.
  w := W3(a = 1, b = 2, c = 3)
  u := unchecked bitcast(Tri(u64), w)
  if u.p != 1 { return 111 }
  if u.q != 2 { return 112 }
  if u.r != 3 { return 113 }

  ## The ENUM sibling of the same target shape: the whole `1 + payload` image must move, so the
  ## payload is checked on its own arm and the wrong-arm case carries its own code. Measured on the
  ## parent this arm alone runs to 114 — the payload word did not move.
  e := Opt(u64).Some(58)
  f := unchecked bitcast(Alt(u64), e)
  match f {
    Alt.Val(x) => { if x != 58 { return 114 } }
    Alt.Nil => { return 115 }
  }

  return 42
}
