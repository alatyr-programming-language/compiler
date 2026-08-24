## Functions §7.2: a SLICE variadic with a STRUCT element `rest : ...Pt` — the trailing call args
## (struct ctors, 2 words each) are gathered into ONE contiguous runtime `[Pt]` data block, and a
## {ptr, len} slice is passed. The callee reads each element BY REFERENCE like a `Slice(Pt)` param
## (`for p in rest`, then `p.a`/`p.b`). The call-site gather lays `stride` words per element, and the
## `...Pt` param binds `eek == 2` (struct) with the element stride + type span.
## psum(Pt(10,11), Pt(20,1)) = (10+11) + (20+1) = 42.
Pt := struct { a : u64, b : u64 }
psum := fn(xs : ...Pt) -> u64 {
  mut s : u64 = 0
  for p in xs {
    s = s + p.a + p.b
  }
  return s
}
main := fn() -> u64 {
  return psum(Pt(a = 10, b = 11), Pt(a = 20, b = 1))
}
