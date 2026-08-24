## e2e: a `Slice(T)` PARAM — `f(xs[lo..hi])`. A slice is a 2-word {ptr, len} passed BY REFERENCE (the
## callee's slot holds a POINTER to the caller's {ptr,len} block, materialized in an agg-temp by
## emit_arg's slice arm). The callee reads it with a DOUBLE deref: `for x in s` and `s[i]` go slot →
## block → data-ptr → element; `s.len()` goes slot → block → len@+8. Distinguished from a LOCAL slice
## VIEW (which holds the data-ptr inline, single deref) by `bind_param`'s `sns == 1` marker. Exercises
## all THREE read paths: for-iteration (20+3+19), indexing (s[0]+s[2] = 20+19), and .len() (3).
sum_iter := fn(s : Slice(u64)) -> u64 {
  mut acc : u64 = 0
  for x in s { acc = acc + x }
  return acc
}
sum_idx := fn(s : Slice(u64)) -> u64 { return s[0] + s[2] }
slen := fn(s : Slice(u64)) -> u64 { return s.len() }
main := fn() -> u64 {
  xs : [u64; 5] = [99, 20, 3, 19, 99]
  a := sum_iter(xs[1..4])   ## 20 + 3 + 19 = 42
  b := sum_idx(xs[1..4])    ## 20 + 19 = 39
  c := slen(xs[1..4])       ## 3
  ## a is the answer; assert b and c via a guard that returns a bogus value if wrong.
  if b != 39 { return 1 }
  if c != 3 { return 2 }
  return a
}
