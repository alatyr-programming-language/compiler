## Issue #857 / Comptime §10 + Types §6.2 — the OVER-REJECTION control: every applied spelling stays accepted in every
## type position (parameter, result, local, struct field, enum payload, user type function, nested).
## It runs to 42.
Box := fn(T : type) -> type { return struct { v : T } }
N := struct { v : u64, o : Option(u64), b : Box(u64) }
E := enum { A(Option(u64), Result(u64, u64)), B(Box(u64)), C }
f := fn(o : Option(u64), b : Box(u64)) -> Option(u64) { o }
main := fn() -> u64 {
  x : Option(u64) = f(Option(u64).Some(40), Box(u64)(v = 1))
  n := N(v = 2, o = Option(u64).None, b = Box(u64)(v = 0))
  e := E.C
  mut t : u64 = n.v
  match x {
    Option::Some(k) => { t += k }
    Option::None => { t = 0 }
  }
  match e {
    E::A(a, b) => { t = 0 }
    E::B(b) => { t = 0 }
    E::C => {}
  }
  return t
}
