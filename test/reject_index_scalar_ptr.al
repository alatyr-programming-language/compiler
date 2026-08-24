## e2e (build_reject) — CORRECT-OR-TRAP: indexing a SCALAR local is not a place. Types §6.4 is
## explicit that "a raw pointer carries no arithmetic indexing of its own, so `[i]` on a pointer always
## means dereference-then-index", and §4.5 (OP-5) resolves the index operator on the POINTEE — so
## `p[i]` is well-formed only when the pointee is INDEXABLE. Here `p : ptr(u8)` (a `str`'s `.ptr`), a
## scalar pointee with no index operator.
## Before the guard the lowering `leaq`'d `p`'s own frame SLOT and treated the surrounding frame as an
## array: `p[0]` read the pointer WORD itself → 0 for every `str`, a SILENT MISCOMPILE (the same shape
## also mis-read `pa := ptr(xs); pa[i]` and `psl := ptr(sl); psl[0]`). The working spellings are
## `deref(p)` for one element and a view (`bytes(s)` / `Slice(T)(ptr = p, len = n)`) for indexing.
main := fn() -> u64 {
  s := "A"
  p := s.ptr
  u64(p[0])
}
