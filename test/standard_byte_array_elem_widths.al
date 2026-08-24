## P1-CLAYOUT S3(d) — the array-element tier at every sub-word CHILD width, and with a byte array
## BEFORE and AFTER the child. Chosen so the word model and the C model disagree on every field but
## the first (audit §7 risk 4's selection criterion):
##   W16 { a : u16, b : u16 }          §6.1 offsets 0, 2      word offsets 0, 8
##   W8  { a : u8,  b : u16 }          §6.1 offsets 0, 2      word offsets 0, 8   (b is 2-ALIGNED, so
##                                     §6.1 pads one byte after `a` — a plain byte cursor says 1)
##   W32 { a : u32, b : u32 }          §6.1 offsets 0, 4      word offsets 0, 8
## and three element types over them, each carrying a byte array on BOTH sides of the child:
##   E16 { pre : [u8;4], inner : W16, post : [u8;4] }   offsets 0, 8, 24   size 32   stride 32
##   E8  { pre : [u8;4], inner : W8,  post : [u8;4] }   offsets 0, 8, 24   size 32   stride 32
##   E32 { pre : [u8;4], inner : W32, post : [u8;4] }   offsets 0, 8, 24   size 32   stride 32
## (`inner` still occupies `struct_words * 8` = 16 bytes at this stage, which is why `post` lands at
## 24 and not at 12 — the point here is the CHILD's internal widths and the two byte arrays, not the
## child's own footprint. The stride shapes live in `standard_byte_array_elem_unaligned.al`.)
##
## FOUR elements, every element and every field read, and the last-written element's neighbours
## re-read afterwards — the aliasing check the stride bug broke.
## Every comparison is INSIDE the program; every value is < 126.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   S3(c) as landed (dd10312)   reject / reject / reject / reject
##   S3(d), this commit              42 / reject / reject / reject
W16 := struct { a : u16, b : u16 }
W8  := struct { a : u8, b : u16 }
W32 := struct { a : u32, b : u32 }
E16 := struct { pre : [u8; 4], inner : W16, post : [u8; 4] }
E8  := struct { pre : [u8; 4], inner : W8, post : [u8; 4] }
E32 := struct { pre : [u8; 4], inner : W32, post : [u8; 4] }
main := fn() -> u64 {
  mut a : [E16; 4]
  a[0] = E16(pre = [1, 2, 3, 4], inner = W16(a = 20, b = 22), post = [5, 6, 7, 8])
  a[1] = E16(pre = [9, 10, 11, 12], inner = W16(a = 24, b = 26), post = [13, 14, 15, 16])
  a[2] = E16(pre = [17, 18, 19, 20], inner = W16(a = 28, b = 30), post = [21, 22, 23, 24])
  a[3] = E16(pre = [25, 26, 27, 28], inner = W16(a = 32, b = 34), post = [29, 30, 31, 32])
  if u64(a[0].pre[0]) != 1 { return 1 }
  if u64(a[0].post[3]) != 8 { return 2 }
  if u64(a[0].inner.a) != 20 { return 3 }
  if u64(a[0].inner.b) != 22 { return 4 }
  if u64(a[1].pre[3]) != 12 { return 5 }
  if u64(a[1].post[0]) != 13 { return 6 }
  if u64(a[1].inner.b) != 26 { return 7 }
  if u64(a[2].pre[1]) != 18 { return 8 }
  if u64(a[2].post[2]) != 23 { return 9 }
  if u64(a[2].inner.b) != 30 { return 10 }
  if u64(a[3].pre[0]) != 25 { return 11 }
  if u64(a[3].post[3]) != 32 { return 12 }
  if u64(a[3].inner.a) != 32 { return 13 }
  if u64(a[3].inner.b) != 34 { return 14 }

  mut b : [E8; 3]
  b[0] = E8(pre = [33, 34, 35, 36], inner = W8(a = 36, b = 38), post = [37, 38, 39, 40])
  b[1] = E8(pre = [41, 42, 43, 44], inner = W8(a = 40, b = 42), post = [45, 46, 47, 48])
  b[2] = E8(pre = [49, 50, 51, 52], inner = W8(a = 44, b = 46), post = [53, 54, 55, 56])
  if u64(b[0].inner.a) != 36 { return 15 }
  if u64(b[0].inner.b) != 38 { return 16 }
  if u64(b[0].pre[0]) != 33 { return 17 }
  if u64(b[0].post[3]) != 40 { return 18 }
  if u64(b[1].inner.a) != 40 { return 19 }
  if u64(b[1].inner.b) != 42 { return 20 }
  if u64(b[2].inner.a) != 44 { return 21 }
  if u64(b[2].inner.b) != 46 { return 22 }
  if u64(b[2].pre[3]) != 52 { return 23 }
  if u64(b[2].post[0]) != 53 { return 24 }

  mut c : [E32; 3]
  c[0] = E32(pre = [57, 58, 59, 60], inner = W32(a = 48, b = 50), post = [61, 62, 63, 64])
  c[1] = E32(pre = [65, 66, 67, 68], inner = W32(a = 52, b = 54), post = [69, 70, 71, 72])
  c[2] = E32(pre = [73, 74, 75, 76], inner = W32(a = 56, b = 58), post = [77, 78, 79, 80])
  if u64(c[0].inner.a) != 48 { return 25 }
  if u64(c[0].inner.b) != 50 { return 26 }
  if u64(c[1].inner.a) != 52 { return 27 }
  if u64(c[1].inner.b) != 54 { return 28 }
  if u64(c[2].inner.a) != 56 { return 29 }
  if u64(c[2].inner.b) != 58 { return 30 }
  if u64(c[1].pre[0]) != 65 { return 31 }
  if u64(c[1].post[3]) != 72 { return 32 }

  ## write element 1 of each, then read k-1 and k+1
  a[1] = E16(pre = [81, 82, 83, 84], inner = W16(a = 60, b = 62), post = [85, 86, 87, 88])
  if u64(a[1].inner.b) != 62 { return 33 }
  if u64(a[0].inner.b) != 22 { return 34 }
  if u64(a[2].inner.b) != 30 { return 35 }
  b[1] = E8(pre = [89, 90, 91, 92], inner = W8(a = 64, b = 66), post = [93, 94, 95, 96])
  if u64(b[1].inner.b) != 66 { return 36 }
  if u64(b[0].inner.b) != 38 { return 37 }
  if u64(b[2].inner.b) != 46 { return 38 }
  c[1] = E32(pre = [97, 98, 99, 100], inner = W32(a = 68, b = 70), post = [101, 102, 103, 104])
  if u64(c[1].inner.b) != 70 { return 39 }
  if u64(c[0].inner.b) != 50 { return 40 }
  if u64(c[2].inner.b) != 58 { return 41 }
  42
}
