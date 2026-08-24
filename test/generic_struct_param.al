## e2e (generic-instance struct-param field read — the tparam-index root fix). A generic fn with a
## STRUCT param BEFORE the type param (`gf(in out s : P, T : type, k)`) mis-bound `s` as a scalar in
## its instance: `emit_fn` is called with `di = 0` for an instance, and `tparam_idx(di)` re-fetched
## decl[0] (some OTHER decl) to locate `T`, returning the wrong index — so the param loop skipped `s`
## instead of `T`, and `s.x` read 0. (It only worked when the generic fn happened to be decl[0].)
## The fix scans THIS decl's own params. Unblocks `allocate(in out self : Arena, T : type, …)`'s
## `self.off`/`self.cap` reads. `s.x`=40 + `k`=2 → 42.
P := struct { x : u64, y : u64 }
gf := fn(in out s : P, T : type, k : usize) -> usize { return s.x + k }
main := fn() -> u64 {
  mut p := P(x = 40, y = 99)
  u64(gf(p, u64, 2))
}
