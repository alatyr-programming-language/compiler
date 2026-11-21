## e2e — IR-38 (#1786 cause 4): `match deref(q)` over an ENUM pointee whose type the operand's
## declaration does not spell; the builder takes it from what sema recorded for the `deref` node
## (docs/ir.md §3.8 item 8):
##   * `r := pick(e)` — an inferred local;
##   * `Some(q)` of an `Option(ptr(E))` — a payload binding of a generic enum instance;
##   * `h.e` — a struct field.
## One variant per check; each check answers its own code when it fails, 42 when all held.
E := enum { A, B(u64), C(u64, u64) }
H := struct { e : ptr(E), k : u64 }

pick := fn(q : ptr(E)) -> ptr(E) { q }

by_local := fn(e : ptr(E)) -> u64 {
  r := pick(e)
  match deref(r) { E.A => { return 1 }; E.B(x) => { return x }; E.C(x, y) => { return x * 10 + y } }
}
by_payload := fn(o : Option(ptr(E))) -> u64 {
  match o {
    Some(q) => { match deref(q) { E.A => { return 1 }; E.B(x) => { return x }; E.C(x, y) => { return x * 10 + y } } }
    None => { return 7 }
  }
}
by_field := fn(h : H) -> u64 {
  match deref(h.e) { E.A => { return h.k }; E.B(x) => { return x }; E.C(x, y) => { return x * 10 + y } }
}

main := fn() -> u64 {
  mut e := E.A
  if by_local(ptr(e)) != 1 { return 1 }
  if by_field(H(e = ptr(e), k = 5)) != 5 { return 2 }
  e = E.B(9)
  if by_local(ptr(e)) != 9 { return 3 }
  if by_payload(Option(ptr(E)).Some(ptr(e))) != 9 { return 4 }
  e = E.C(3, 4)
  if by_payload(Option(ptr(E)).Some(ptr(e))) != 34 { return 5 }
  if by_field(H(e = ptr(e), k = 5)) != 34 { return 6 }
  if by_payload(Option(ptr(E)).None) != 7 { return 7 }
  42
}
## expect: run 42
