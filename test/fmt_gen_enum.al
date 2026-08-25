## fmt — a GENERIC enum declaration with a type-parameter header round-trips (§5 tooling). The header
## (the generic-struct/enum tier; parsed by the parser's `skip_type_param`,
## stored on the Decl only as `is_generic`) must survive the format, else fmt is NON-idempotent AND
## changes meaning (generic → non-generic). Two instantiations at DISTINCT payload types (u64 and a
## nested Box(u64)) prove the header is not tied to one element type. Result = 40 + 2 = 42.
Box(T) := enum { Wrap(T), Empty }

Opt(T) := enum { Some(T), None }

main := fn() -> u64 {
  a := Opt.Some(40)
  av := match a {
    Opt.Some(v) => { v }
    Opt.None => { 0 }
  }
  b := Box.Wrap(2)
  bv := match b {
    Box.Wrap(w) => { w }
    Box.Empty => { 0 }
  }
  return av + bv
}
