## #1181 / #1349 — `.len` on an element of a struct field of type `[Slice(u8); N]` is refused on x86_64,
## located, until the field-array path reads the element's two-word pair. The parent accepted it and
## exited 2 where 23 was due (a silent wrong value).
S := struct { k : u64, v : [Slice(u8); 2] }
main := fn() -> u64 {
  a : [u8; 3] = [1, 2, 3]
  b : [u8; 2] = [4, 5]
  s := S(k = 1, v = [a[0..3], b[0..2]])
  u64(s.v[1].len) * 10 + u64(s.v[0].len)
}
## expect: reject "is not supported on x86_64 (#1349)"
