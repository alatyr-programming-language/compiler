## CLAYOUT S3(b) — the byte-precise whole-value writer at every sub-word FIELD WIDTH, and at a
## MIXED width where the §6.1 padding rule is load-bearing. Chosen so the word model and the C model
## disagree on every field but the first (audit §7 risk 4's selection criterion):
##   W32 { a : u32, b : u32 }        §6.1 offsets 0, 4      word offsets 0, 8
##   W8  { a : u8,  b : u16 }        §6.1 offsets 0, 2      word offsets 0, 8   (b is 2-ALIGNED, so
##                                   §6.1 pads one byte after `a` — a plain byte cursor would say 1)
##   W3  { a : u8,  b : u32, c : u8} §6.1 offsets 0, 4, 8   word offsets 0, 8, 16
##   WS  { a : i8,  b : i16, c : i32 } same offsets as W3 — and SIGNED, so the read must
##                                   sign-extend from the field's own width, not from a word
##   WB  { ok : bool, n : u16 }      §6.1 offsets 0, 2       word offsets 0, 8   (bool is 1 byte)
## Every comparison is INSIDE the program (exit codes truncate mod 256) and every value is < 126.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime):
##   S3(a) as landed 22acca6     reject / trap / trap / trap
##   S3(b), this commit              42 /   42 /   42 /   42
W32 := struct { a : u32, b : u32 }
W8  := struct { a : u8, b : u16 }
W3  := struct { a : u8, b : u32, c : u8 }
WS  := struct { a : i8, b : i16, c : i32 }
WB  := struct { ok : bool, n : u16 }
O32 := struct { data : [u8; 8], inner : W32 }
O8  := struct { data : [u8; 8], inner : W8 }
O3  := struct { data : [u8; 8], inner : W3 }
OS  := struct { data : [u8; 8], inner : WS }
OB  := struct { data : [u8; 8], inner : WB }
main := fn() -> u64 {
  mut x := O32(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = W32(a = 20, b = 22))
  if x.inner.a != 20 { return 1 }
  if x.inner.b != 22 { return 2 }
  if x.data[0] != 1 { return 3 }
  if x.data[7] != 8 { return 4 }

  mut y := O8(data = [9, 10, 11, 12, 13, 14, 15, 16], inner = W8(a = 24, b = 26))
  if y.inner.a != 24 { return 5 }
  if y.inner.b != 26 { return 6 }
  if y.data[0] != 9 { return 7 }
  if y.data[7] != 16 { return 8 }

  mut z := O3(data = [17, 18, 19, 20, 21, 22, 23, 24], inner = W3(a = 28, b = 30, c = 32))
  if z.inner.a != 28 { return 9 }
  if z.inner.b != 30 { return 10 }
  if z.inner.c != 32 { return 11 }
  if z.data[0] != 17 { return 12 }
  if z.data[7] != 24 { return 13 }

  mut sg := OS(data = [25, 26, 27, 28, 29, 30, 31, 32], inner = WS(a = 0 - 3, b = 0 - 300, c = 0 - 70000))
  if sg.inner.a != 0 - 3 { return 14 }
  if sg.inner.b != 0 - 300 { return 15 }
  if sg.inner.c != 0 - 70000 { return 16 }
  if sg.data[0] != 25 { return 17 }

  mut bl := OB(data = [33, 34, 35, 36, 37, 38, 39, 40], inner = WB(ok = true, n = 34))
  if not bl.inner.ok { return 18 }
  if bl.inner.n != 34 { return 19 }
  if bl.data[7] != 40 { return 20 }

  ## the five locals must not have overlapped: re-read the earlier ones last
  if x.inner.b != 22 { return 21 }
  if y.inner.b != 26 { return 22 }
  if z.inner.c != 32 { return 23 }
  if sg.inner.c != 0 - 70000 { return 24 }
  42
}
