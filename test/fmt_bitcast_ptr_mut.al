## e2e/fmt — a SUB-WORD pointee bitcast keeps the `mut` marker the source wrote. The parser preserves
## only the POINTEE span for `bitcast(ptr(<sub-word scalar>), v)` (`p_factor`'s bitcast branch keeps
## `u8`, not `ptr(mut u8)`), so `mut` is absent from the AST entirely and fmt re-emitted `ptr(u8)` for
## BOTH spellings — the same program today (pointer mutability is not yet enforced) but a different
## SOURCE, and a build break the day it is. Recovered by the same source-scan `Expr::AddrOf` already
## uses for `ptr(mut x)` (`ast::local_is_mut` off the pointee's own span start): inside a `ptr(` the
## only token that can precede the pointee is the `mut` marker itself, so there is no false match.
##
## Both spellings appear below so a fix cannot pass by simply ALWAYS writing `mut`: `wp` is written
## `ptr(mut u8)` and must come back with the marker, `rp` is written `ptr(u8)` and must come back
## without it. Behaviour is identical either way — the `fmt-has` needles are the real assertion.
main := fn() -> u64 {
  mut cell : u64 = 0
  addr := unchecked bitcast(usize, ptr(mut cell))
  wp := unchecked bitcast(ptr(mut u8), addr)
  deref(wp) = 42
  rp := unchecked bitcast(ptr(u8), addr)
  if u64(deref(rp)) != 42 { return 1 }
  u64(deref(rp))
}
