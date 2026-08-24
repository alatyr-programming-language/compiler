## e2e (§3 — a RANGE `comptime for` whose bound is `typeinfo(T).n`, the comptime array length). In a
## generic instance where `T` is an array `[E; N]`, `typeinfo(T).n` resolves to `N` (via `parse_arr_len`
## on the instance type `cx.it`, in `comptime_range_bound`), so `comptime for i in 0 .. typeinfo(T).n`
## unrolls exactly N times with `i` a compile-time constant — the mechanism `lib/base/derive.al`'s
## `Array(_)` arm relies on to fold over array elements. Here the body accumulates the index `i`
## (0+1+2+3 = 6 for N=4), keeping the test to the bound-evaluation + unroll (not array-element access).
count_to_n := fn(T : type, a : T) -> u64 {
  mut s : u64 = 0
  comptime for i in 0 .. typeinfo(T).n { s = s + i }
  return s
}
main := fn() -> u64 {
  arr : [u64; 4] = [9, 9, 9, 9]
  count_to_n([u64; 4], arr) + 36   ## N=4 → 0+1+2+3 = 6; 6 + 36 = 42
}
