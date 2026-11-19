## e2e — #1758 (IR-33): `Slice(T)(ptr = p, len = n)` is a view built from its two words. Stdlib appendix
## §3.5 declares the slice as the library pair `struct { ptr : ptr(T), len : usize }`, so the literal IS
## the view's pair: `ptr` at byte 0, `len` at byte 8 (Types §6.1, declaration order). The shared IR builds
## it as a view local, its `ptr` the address of a literal element of an array local: a narrow element
## (stride 1, Types §6.4) read by `for` and through `.len`, and a word element read by index. Before the
## IR built these, every twin trapped here (the legacy `ptr(b[k])` stub, #1188).
## 3 + 20 + 5 + len 3 = 31, + (9 - 8) = 32, + 10 = 42.
## expect: run 42
narrow_sum := fn() -> u64 {
  b : [u8; 6] = [1, 2, 3, 20, 5, 6]
  s := Slice(u8)(ptr = ptr(b[2]), len = 3)
  mut acc : u64 = 0
  for x in s { acc = acc + u64(x) }
  acc + u64(s.len)
}

word_step := fn() -> u64 {
  w : [u64; 3] = [7, 8, 9]
  t := Slice(u64)(ptr = ptr(w[1]), len = 2)
  t[1] - t[0]
}

main := fn() -> u64 {
  narrow_sum() + word_step() + 10
}
