## extract an AGGREGATE field of a local struct into a local (`x := s.f` where f is a
## struct or enum field). The scalar store delivered only word 0, so `inner := b.a` / `c := s.c`
## silently produced 0. Now field_read_agg binds x as the field's aggregate type and the emit copies
## its words from the base struct. Struct-field extract + enum-field extract in one program.
A := struct { v : u64, w : u64 }
Col := enum { R, G(u64) }
B := struct { a : A, c : Col, n : u64 }
main := fn() -> u64 {
  b := B(a = A(v = 20, w = 1), c = Col.G(20), n = 1)
  inner := b.a                                  ## struct-field extract
  cc := b.c                                     ## enum-field extract
  return inner.v + inner.w + match cc { Col::R => { 0 }; Col::G(x) => { x } } + b.n
}
