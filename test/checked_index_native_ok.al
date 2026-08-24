## CG-6 neutrality guard: a NATIVE-width `[u64; N]` index add is UNAFFECTED by the element-type
## recovery — `u64` is not a narrow width, so `expr_type_span(xs[i])` returns 0/0 exactly as before
## and no per-width narrow trap is added (the native-width overflow guard already applied). 40 + 2 = 42.
main := fn() -> u64 {
  xs : [u64; 4] = [40, 2, 1, 2]
  i : u64 = 0
  j : u64 = 1
  return xs[i] + xs[j]
}
