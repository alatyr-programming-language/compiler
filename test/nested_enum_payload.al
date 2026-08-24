## e2e (§4 layout — a NESTED enum payload: an enum whose variant payload is ANOTHER enum). A payload
## of enum type occupies the inner enum's full `[disc, payload…]` width, so the construction
## `Outer.X(Inner.A(40))` must store the inner enum's words recursively (via emit_enum_assign at the
## payload slot), and the outer `match X(i)` binds `i` as the inner enum (ek 3) so a nested
## `match i { A(v) => … }` reads its disc + payload. Previously the inner enum payload was stored as
## one word (emit_gas), truncating it → the nested match read a garbage disc/value.
Inner := enum { A(u64), B }
Outer := enum { X(Inner), Y(u64) }

unwrap := fn(o : Outer) -> u64 {
  match o {
    X(i) => { match i { A(v) => { return v } B => { return 0 } } }
    Y(k) => { return k }
  }
}

main := fn() -> u64 {
  a := unwrap(Outer.X(Inner.A(40)))   ## 40
  b := unwrap(Outer.Y(2))             ## 2
  a + b                               ## 42
}
