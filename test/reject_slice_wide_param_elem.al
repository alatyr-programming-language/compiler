## #1181 — a `Slice(Slice(u64))` parameter is refused on x86_64 until an index into its element reads a
## `u64`, not a byte (Types §7). The parent read its elements at a one-word stride.
f := fn(xs : Slice(Slice(u64))) -> u64 {
  u64(xs[1].len) * 10 + u64(xs[0].len)
}

main := fn() -> u64 {
  f(Slice(Slice(u64))(ptr = unchecked bitcast(ptr(Slice(u64)), 8), len = 0))
}
