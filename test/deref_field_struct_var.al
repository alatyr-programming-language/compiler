## e2e — a MULTI-WORD struct FIELD written THROUGH a pointer from a local struct VAR (`deref(p).i = nv`).
## Previously FAIL-LOUD: the shared multi-word-field helper's per-word copy loop is mis-lowered by the
## seed (collapsed to a single word). The fix delivers the struct VAR INLINE in the FieldPathAssign emit
## arm — the copy loop runs at COMPILE time there (a pre-existing emit fn the seed lowers correctly), so
## the emitted code is fully UNROLLED straight-line stores, NOT the extracted-helper loop. A local
## struct's word k lives at `push_frame_word(off, k)`; both words land + the neighbour field `t` is
## untouched. 30 + 7 + 5 = 42. x86-only delivery path. Neutral: src/+lib/ never do this.
Inner := struct { v : u64, w : u64 }
Outer := struct { i : Inner, t : u64 }
main := fn() -> u64 {
  mut o := Outer(i = Inner(v = 0, w = 0), t = 5)
  nv := Inner(v = 30, w = 7)
  p := ptr(mut o)
  deref(p).i = nv                     ## multi-word struct VAR written through a pointer
  o.i.v + o.i.w + o.t                 ## 30 + 7 + 5 = 42 (both field words + neighbour intact)
}
