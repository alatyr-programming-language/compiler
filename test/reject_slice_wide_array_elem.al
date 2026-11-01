## #1181 — a `[Slice(u64); N]` element is refused on x86_64 until an index into it reads a `u64`, not a
## byte (Types §7). The parent accepted the declaration and stored one word per element.
main := fn() -> u64 {
  a : [u64; 3] = [1, 2, 3]
  b : [u64; 2] = [4, 5]
  t : [Slice(u64); 2] = [a[0..3], b[0..2]]
  t[1][0] * 10 + t[0][1]
}
