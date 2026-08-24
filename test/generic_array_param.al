## e2e (§4 — indexing a GENERIC array parameter). A generic fn `fn(T : type, a : T)` instantiated with
## an array type `T = [E; N]` must bind `a` as an ARRAY (ek 5, by-ref) with the element stride resolved
## from the SUBSTITUTED type — `a`'s syntax was the bare `T` (pmode 0), so `bind_param` previously fell
## to the scalar fallthrough and `a[i]` mis-read. Now the substituted `[E; N]` is detected and the
## element layout resolved. Combines with the range `comptime for` over `typeinfo(T).n` (the shape
## `lib/base/derive.al`'s `Array(_)` eq/lt uses: `a[i] != b[i]`). `src/`+`lib/` instantiate no generic
## array param over a concrete array, so this stays fixpoint-neutral.
sum_gen := fn(T : type, a : T) -> u64 {
  mut s : u64 = 0
  mut i : usize = 0
  while i < 3 { s = s + a[i]; i = i + 1 }   ## runtime index of a generic array param
  return s
}
fold_ct := fn(T : type, a : T) -> u64 {
  mut s : u64 = 0
  comptime for i in 0 .. typeinfo(T).n { s = s + a[i] }   ## comptime-unrolled index (derive shape)
  return s
}
main := fn() -> u64 {
  arr : [u64; 3] = [12, 20, 10]
  a := sum_gen([u64; 3], arr)    ## 42
  b := fold_ct([u64; 3], arr)    ## 42
  if a == 42 and b == 42 { return 42 }
  1
}
