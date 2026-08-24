## CLAYOUT S3(d) — the shape where the byte STRIDE and `struct_words * 8` genuinely DISAGREE, and
## where the child sits at a NON-8-ALIGNED element offset. This is the fixture that falsifies "the
## stride was already right": the previous element addressing multiplied the index by
## `struct_words * 8`, which is 16 here, while Types §6.4 requires 10.
##
## Layout, per Types §6.1/§6.4:
##   Mid { lead : u16, raw : [u8; 2], tail : u16 }    offsets 0, 2, 4   size 6    align 2
##   Un  { data : [u8; 3], inner : Mid }              offsets 0, 4      size 10   align 2
##                                                    stride 10   (`struct_words * 8` = 16)
##   Bo  { pre : [u8; 2], inner : Mid, post : [u8; 2] } offsets 0, 2, 8  size 10  align 2
##                                                    stride 10   (`struct_words * 8` = 16)
## `inner` is a BYTE-tier child (it carries its own `[u8; 2]`), so it has a real §6.1 alignment of 2
## rather than the flat 8 a non-byte aggregate reports — which is what lets the parent place it at
## byte 4 (`Un`) and byte 2 (`Bo`). `raw` is written BETWEEN `lead` and `tail`, so a raw store landing
## at the wrong offset shows up as a wrong `lead` or `tail`.
##
## Three elements, every element and every field, plus the write-k / read-k±1 aliasing check — AND a
## direct measurement of the stride itself, which the value reads alone do NOT give. That distinction is
## worth stating, because it was measured rather than assumed: with the byte stride forced back to
## `struct_words * 8` = 16 (a one-line mutation of `slot_elem_stride_bytes`) every value comparison in
## this file still passed, because 16 > 10 so nothing aliases and the writes and reads agree with each
## other on the same wrong number. What falsifies it is the ADDRESS: `ptr(u[1]) - ptr(u[0])` must be 10,
## and `size([Un; 3])` must be 30 — the type-level footprint every other consumer of the array (a `[Un;
## N]` field's §6.1 size, an FFI hand-off, `typeinfo`) is computed from. Under the mutation that block
## returns 1; correct, it returns 42.
## Every comparison is INSIDE the program; every value is < 126.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   S3(c) as landed (dd10312)   reject / reject / reject / reject
##   S3(d), this commit              42 / reject / reject / reject
Mid := struct { lead : u16, raw : [u8; 2], tail : u16 }
Un  := struct { data : [u8; 3], inner : Mid }
Bo  := struct { pre : [u8; 2], inner : Mid, post : [u8; 2] }
main := fn() -> u64 {
  mut u : [Un; 3]
  u[0] = Un(data = [1, 2, 3], inner = Mid(lead = 20, raw = [4, 5], tail = 22))
  u[1] = Un(data = [6, 7, 8], inner = Mid(lead = 24, raw = [9, 10], tail = 26))
  u[2] = Un(data = [11, 12, 13], inner = Mid(lead = 28, raw = [14, 15], tail = 30))
  if u64(u[0].data[0]) != 1 { return 1 }
  if u64(u[0].data[2]) != 3 { return 2 }
  if u64(u[0].inner.lead) != 20 { return 3 }
  if u64(u[0].inner.tail) != 22 { return 4 }
  if u64(u[1].data[0]) != 6 { return 5 }
  if u64(u[1].data[2]) != 8 { return 6 }
  if u64(u[1].inner.lead) != 24 { return 7 }
  if u64(u[1].inner.tail) != 26 { return 8 }
  if u64(u[2].data[0]) != 11 { return 9 }
  if u64(u[2].data[2]) != 13 { return 10 }
  if u64(u[2].inner.lead) != 28 { return 11 }
  if u64(u[2].inner.tail) != 30 { return 12 }

  ## write the middle element, then read its neighbours
  u[1] = Un(data = [16, 17, 18], inner = Mid(lead = 32, raw = [19, 20], tail = 34))
  if u64(u[1].inner.tail) != 34 { return 13 }
  if u64(u[1].data[1]) != 17 { return 14 }
  if u64(u[0].inner.tail) != 22 { return 15 }
  if u64(u[0].data[2]) != 3 { return 16 }
  if u64(u[2].inner.tail) != 30 { return 17 }
  if u64(u[2].data[0]) != 11 { return 18 }

  ## a byte array on BOTH sides of a byte-tier child, child at byte 2
  mut b : [Bo; 3]
  b[0] = Bo(pre = [21, 22], inner = Mid(lead = 36, raw = [23, 24], tail = 38), post = [25, 26])
  b[1] = Bo(pre = [27, 28], inner = Mid(lead = 40, raw = [29, 30], tail = 42), post = [31, 32])
  b[2] = Bo(pre = [33, 34], inner = Mid(lead = 44, raw = [35, 36], tail = 46), post = [37, 38])
  if u64(b[0].pre[0]) != 21 { return 19 }
  if u64(b[0].pre[1]) != 22 { return 20 }
  if u64(b[0].inner.lead) != 36 { return 21 }
  if u64(b[0].inner.tail) != 38 { return 22 }
  if u64(b[0].post[0]) != 25 { return 23 }
  if u64(b[0].post[1]) != 26 { return 24 }
  if u64(b[1].pre[0]) != 27 { return 25 }
  if u64(b[1].inner.lead) != 40 { return 26 }
  if u64(b[1].inner.tail) != 42 { return 27 }
  if u64(b[1].post[1]) != 32 { return 28 }
  if u64(b[2].pre[1]) != 34 { return 29 }
  if u64(b[2].inner.lead) != 44 { return 30 }
  if u64(b[2].inner.tail) != 46 { return 31 }
  if u64(b[2].post[0]) != 37 { return 32 }

  b[1] = Bo(pre = [39, 40], inner = Mid(lead = 48, raw = [41, 42], tail = 50), post = [43, 44])
  if u64(b[1].inner.tail) != 50 { return 33 }
  if u64(b[0].inner.tail) != 38 { return 34 }
  if u64(b[0].post[1]) != 26 { return 35 }
  if u64(b[2].inner.tail) != 46 { return 36 }
  if u64(b[2].pre[0]) != 33 { return 37 }

  ## a nested scalar store through the element place, then the neighbours again
  b[2].inner.tail = 52
  if u64(b[2].inner.tail) != 52 { return 38 }
  if u64(b[2].inner.lead) != 44 { return 39 }
  if u64(b[2].post[0]) != 37 { return 40 }
  if u64(b[1].inner.tail) != 50 { return 41 }

  ## THE STRIDE ITSELF (Types §6.4: stride = size rounded up to align). This is the only part of the
  ## file a wrong stride can fail: consecutive element ADDRESSES must be exactly `size(Un)` apart, and
  ## `size([Un; 3])` must be three of them. `align(Un)` is 2 because `inner` is a byte-tier child that
  ## reports a real §6.1 alignment, which is what makes the size 10 rather than a rounded 16.
  a0 := unchecked bitcast(usize, ptr(u[0]))
  a1 := unchecked bitcast(usize, ptr(u[1]))
  a2 := unchecked bitcast(usize, ptr(u[2]))
  if a1 - a0 != 10 { return 43 }
  if a2 - a1 != 10 { return 44 }
  if size(Un) != 10 { return 45 }
  if align(Un) != 2 { return 46 }
  if size([Un; 3]) != 30 { return 47 }
  b0 := unchecked bitcast(usize, ptr(b[0]))
  b1 := unchecked bitcast(usize, ptr(b[1]))
  if b1 - b0 != 10 { return 48 }
  if size(Bo) != 10 { return 49 }
  if align(Bo) != 2 { return 50 }
  42
}
