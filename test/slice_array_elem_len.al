## #1181 — an element of `[Slice(u8); N]` holds its two-word {ptr, len} pair (Types §7: a view "array
## element holds the two-word pair itself"), whatever the element's syntax. Expected exit 23: the
## lengths 2 and 3. The parent kept one word per element and refused the `.len` read.
main := fn() -> u64 {
  a : [u8; 3] = [1, 2, 3]
  b : [u8; 2] = [4, 5]
  t : [Slice(u8); 2] = [a[0..3], b[0..2]]
  u64(t[1].len) * 10 + u64(t[0].len)
}
