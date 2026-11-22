## Issue #1859 — with a `#` comment between the name and the `:`, `v : [u64; 2] = deref(p)` still
## copies the whole array, so `v.len` is 2 (Types §6.4). The lost annotation made it `v := deref(p)`,
## which bound one word and answered 40.
rd := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  v # the pair
    : [u64; 2] = deref(p)
  v.len + v[0] + v[1] - 2
}
main := fn() -> u64 {
  mut arr : [u64; 2] = [40, 2]
  rd(unchecked bitcast(usize, ptr(arr)))
}
## spec: Grammar §2.5; Types §6.4
## expect: run 42
