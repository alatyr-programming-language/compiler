## e2e / issue #852 — `Option(ptr(T))` as a payload component of another enum's variant.
##
## A folded `Option(ptr(T))` is one word in every position. As a variant payload it was stored as a
## two-word enum (the construction from a folded local was refused outright), and a match binding over
## it was untyped, so `match q { Some(r) => … }` inside the arm was refused. The component's declared type
## now decides: the construction (local store and return registers) writes the one folded word and the
## binding is typed as the folded Option. First, middle, last and only positions; two folded payloads;
## construct, match, rebind, pass and return.
##
## 42 means every payload held. Each miss owns its own code from 100 up.
N := struct { v : u64 }
E := enum { A(Option(ptr(mut N)), u64, Option(ptr(mut N))), B(Option(ptr(mut N))), C }
M := enum { X(u64, Option(ptr(mut N)), u64), Y }

val := fn(o : Option(ptr(mut N))) -> u64 { match o { Some(r) => { return deref(r).v }; None => { return 0 } }; 0 }
take := fn(e : E) -> u64 {
  match e {
    A(p, k, q) => { return val(p) + k + val(q) }
    B(p) => { return val(p) + 1 }
    C => { return 0 }
  }
  0
}
mk := fn(p : ptr(mut N)) -> E { E.B(Option.Some(p)) }
mk2 := fn(p : ptr(mut N), k : u64) -> E { E.A(Option.None, k, Option.Some(p)) }

main := fn() -> u64 {
  mut n := N(v = 10)
  mut m := N(v = 20)
  ## the issue's two reproducers: from a folded local, and inline, matched through the binding
  h : Option(ptr(mut N)) = Option.Some(ptr(mut n))
  x1 := M.X(30, h, 2)
  match x1 { X(a, q, c) => { match q { Some(r) => { if deref(r).v + a + c != 42 { return 100 } }; None => { return 101 } } }; Y => { return 102 } }
  x2 := M.X(30, Option.Some(ptr(mut n)), 2)
  match x2 { X(a, q, c) => { match q { Some(r) => { if deref(r).v + a + c != 42 { return 103 } }; None => { return 104 } } }; Y => { return 105 } }
  ## two folded payloads, first and last, passed by value
  if take(E.A(Option.Some(ptr(mut n)), 2, Option.Some(ptr(mut m)))) != 32 { return 106 }
  if take(E.A(Option.None, 3, Option.Some(ptr(mut n)))) != 13 { return 107 }
  ## the only payload, None and Some, and returned from a function
  if take(E.B(Option.None)) != 1 { return 108 }
  if take(mk(ptr(mut m))) != 21 { return 109 }
  if take(mk2(ptr(mut m), 1)) != 21 { return 110 }
  ## a rebind of an enum local, then a value match
  mut e := E.C
  e = E.A(Option.Some(ptr(mut m)), 22, Option.None)
  r := match e { A(p, k, q) => { val(p) + k + val(q) }; B(p) => { 200 }; C => { 201 } }
  r
}
