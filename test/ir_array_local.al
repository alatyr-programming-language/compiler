## IR slice 3c (`docs/ir-slice-3.md` §7): a fixed array LOCAL `[T; N]` of a kernel scalar is a frame
## object on the register twins — element `i` at `i * stride` (Types §6.4), the element's width and
## signedness taken from sema's record of the read (#707's mechanism). Exercised: literal and dynamic
## index reads and writes, a fill `[v; N]`, narrow elements that compare and divide at their own
## signedness, a `bool` element, and an index inside `unchecked`. Measured on the parent: the legacy
## aarch64/riscv64 emitters answered 93 — `signed_narrow` divided the `i8` element -5 as the unsigned
## byte 251 (251 / 5 = 50) — where x86_64 and wasm answer 42. Every backend answers 42 here because the
## shapes the IR also builds but a legacy reference gets wrong are left out: x86_64's #909, #936 and
## #937, and legacy wasm's `.len` of a local (a trap) and array reassignment (a wrong value), which
## wasm keeps until its shadow stack lets it select arrays.
sum := fn() -> u64 {
  mut a : [u64; 4] = [10, 20, 30, 40]
  mut s : u64 = 0
  for i in 0..4 { s = s + a[i] }
  a[3] = 2
  s + a[3] - 100
}
narrow := fn() -> u64 {
  mut b : [u8; 3] = [200, 7, 9]
  w : [i16; 2] = [0 - 300, 5]
  if b[0] < b[1] { return 1 }
  t : i16 = w[0] + w[1]
  if t != 0 - 295 { return 2 }
  mut k : usize = 2
  b[k] = b[k] + 1
  u64(b[2])
}
signed_narrow := fn() -> u64 {
  xs : [i8; 3] = [0 - 5, 3, 0 - 128]
  if xs[0] > xs[1] { return 50 }
  t : i8 = xs[0] / 5
  u64(i64(t) + 2)
}
fills := fn() -> u64 {
  mut xs : [u64; 3] = [0; 3]
  xs[1] = 7
  xs[0] = 4
  xs[2] = 1
  mut f : [bool; 2] = [false; 2]
  f[1] = true
  if f[0] or not f[1] { return 100 }
  mut j : usize = 0
  while j < 3 { unchecked { xs[j] = xs[j] + 1 }; j = j + 1 }
  xs[0] + xs[1] - 1
}
main := fn() -> u64 {
  r1 := sum()
  r2 := narrow()
  r3 := fills()
  r4 := signed_narrow()
  if r1 != 2 { return 1 }
  if r2 != 10 { return 2 }
  if r3 != 12 { return 3 }
  r1 + r2 + r3 + r4 + 17
}
## expect: run 42
