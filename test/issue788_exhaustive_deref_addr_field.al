## Issue #788 / Control Flow §5.1 — the over-rejection control for the field read through an
## address-of: a `match deref(ptr(h)).t` naming every variant is exhaustive and `check` accepts it.
## (`build` still refuses this spelling for a lowering reason, #716; the checker's verdict is the
## property under test here.)
C := enum { R, G, B }
H := struct { t : C }
main := fn() -> u64 {
  h := H(t = C.R)
  match deref(ptr(h)).t { R => { return 42 }; G => { return 2 }; B => { return 3 } }
  return 0
}
