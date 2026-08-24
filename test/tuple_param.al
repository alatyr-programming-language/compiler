## §4/§8: runtime tuple element access `t.N` (dot-int index) on a by-ref tuple PARAMETER. A tuple-type
## param `(u64, u64)` is now bound as a by-ref aggregate (like an array param) instead of a scalar, so
## `t.0`/`t.1` read the right words. sum2((40, 2)) = 42. (Was a silent miscompile — returned 120.)
sum2 := fn(t : (u64, u64)) -> u64 {
  return t.0 + t.1
}

main := fn() -> u64 {
  p := (40, 2)
  return sum2(p)
}
