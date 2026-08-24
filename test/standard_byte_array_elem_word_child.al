## CLAYOUT S3(d) — the program `reject_standard_byte_array_elem_field.al` was registered to REFUSE,
## now composed. Same declarations, same reads, deliberately a separate file: the reject fixture keeps
## its three `emit_reject_has` lines (the aarch64/riscv64/wat fence still stands) and this one carries
## the x86_64 coverage as a `run_x86` line, so neither claim has to be read out of the other's name.
##
## The shape matters on its own: the element's nested child is WORD-GRANULAR (`{ x : u64, y : u64 }` —
## every field 8 bytes wide and 8-aligned), so inside the element the two layout models COINCIDE and the
## only thing that ever needed fixing was the hop ACROSS the byte array. `layout_field_offset_bytes`
## answers `field_word_offset * 8` for such a child, which is why one query serves both tiers.
##
## Layout, per Types §6.1/§6.4:
##   Inner { x : u64, y : u64 }             offsets 0, 8    size 16   align 8
##   Outer { data : [u8; 4], inner : Inner} offsets 0, 8    size 24   align 8   stride 24
## `inner` is at byte 8 (`data` is FOUR BYTES, then §6.1 pads to the child's 8-alignment), where the
## word model put it at word 4 = byte 32 — the 24-byte disagreement the fence was measuring.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   pre-S3(b) (495e842)              1 /      1 /      1 /      1   <- WRONG on all four
##   S3(c) as landed (dd10312)   reject / reject / reject / reject
##   S3(d), this commit              42 / reject / reject / reject
Inner := struct { x : u64, y : u64 }
Outer := struct { data : [u8; 4], inner : Inner }
main := fn() -> u64 {
  mut xs : [Outer; 3]
  xs[0] = Outer(data = [1, 2, 3, 4], inner = Inner(x = 20, y = 22))
  xs[1] = Outer(data = [5, 6, 7, 8], inner = Inner(x = 24, y = 26))
  xs[2] = Outer(data = [9, 10, 11, 12], inner = Inner(x = 28, y = 30))
  if xs[0].inner.x != 20 { return 1 }
  if xs[0].inner.y != 22 { return 2 }
  if xs[1].inner.x != 24 { return 3 }
  if xs[1].inner.y != 26 { return 4 }
  if xs[2].inner.x != 28 { return 5 }
  if xs[2].inner.y != 30 { return 6 }
  if u64(xs[0].data[0]) != 1 { return 7 }
  if u64(xs[0].data[3]) != 4 { return 8 }
  if u64(xs[1].data[0]) != 5 { return 9 }
  if u64(xs[2].data[3]) != 12 { return 10 }

  ## write the middle element, then read its neighbours
  xs[1] = Outer(data = [13, 14, 15, 16], inner = Inner(x = 32, y = 34))
  if xs[1].inner.y != 34 { return 11 }
  if xs[0].inner.y != 22 { return 12 }
  if xs[2].inner.y != 30 { return 13 }
  if u64(xs[0].data[3]) != 4 { return 14 }
  if u64(xs[2].data[0]) != 9 { return 15 }

  ## the nested WORD leaf store, and the byte-array store beside it
  xs[2].inner.y = 36
  if xs[2].inner.y != 36 { return 16 }
  if xs[2].inner.x != 28 { return 17 }
  if u64(xs[2].data[3]) != 12 { return 18 }
  xs[0].data[1] = 99
  if u64(xs[0].data[1]) != 99 { return 19 }
  if u64(xs[0].data[0]) != 1 { return 20 }
  if xs[0].inner.x != 20 { return 21 }

  ## the whole element out, and back in
  e := xs[1]
  if e.inner.x != 32 { return 22 }
  if e.inner.y != 34 { return 23 }
  if u64(e.data[0]) != 13 { return 24 }
  xs[2] = e
  if xs[2].inner.y != 34 { return 25 }
  if u64(xs[2].data[3]) != 16 { return 26 }
  if xs[1].inner.y != 34 { return 27 }
  if xs[0].inner.y != 22 { return 28 }

  ## the stride itself: Types §6.4, size rounded up to align
  a0 := unchecked bitcast(usize, ptr(xs[0]))
  a1 := unchecked bitcast(usize, ptr(xs[1]))
  if a1 - a0 != 24 { return 29 }
  if size(Outer) != 24 { return 30 }
  if align(Outer) != 8 { return 31 }
  42
}
