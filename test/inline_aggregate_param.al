## Proposal #3 / Codegen §3.5: an @inline function with a concrete aggregate
## Slice(u8) parameter must receive the complete two-word view at its call site.
## This is the exact codec seam: the inline body indexes the aggregate parameter,
## so a scalarized or ordinary-call fallback is exposed by the result. 42.
@inline
head := fn(s : Slice(u8)) -> u8 { s[0] }

main := fn() -> u64 {
  mut buf : [u8; 2] = [42, 0]
  s := Slice(u8)(ptr = ptr(buf[0]), len = 2)
  u64(head(s))
}
