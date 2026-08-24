## CLAYOUT S3(d) — the S3(c) COPIER's path THROUGH an array element: `e := xs[i]` copies a whole
## element out into a standalone local, which is the read-side mirror of `xs[i] = Elem(…)`.
##
## `std_copy_kind` answers 1 (IMAGE) for both element types here — the destination local's own tier is
## BYTE, so it is read at exactly the source's §6.1 offsets and the copy moves the element's byte image
## verbatim. The number of bytes moved is the element's own `standard_struct_bytes`, NOT
## `struct_words * 8`: for `Un` that is 10 against 16, and copying 16 would read 6 bytes of the NEXT
## element and write them past the destination local's own image.
##
## Layout, per Types §6.1/§6.4:
##   Leaf { a : u16, b : u16 }              offsets 0, 2   size 4    align 2
##   Elem { data : [u8; 8], inner : Leaf }  offsets 0, 8   size 24   align 8   stride 24
##   Mid  { lead : u16, raw : [u8; 2], tail : u16 }  offsets 0, 2, 4  size 6   align 2
##   Un   { data : [u8; 3], inner : Mid }   offsets 0, 4   size 10   align 2   stride 10
##
## Every comparison is INSIDE the program; every value is < 126.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   S3(c) as landed (dd10312)   reject / reject / reject / reject
##   S3(d), this commit              42 / reject / reject / reject
Leaf := struct { a : u16, b : u16 }
Elem := struct { data : [u8; 8], inner : Leaf }
Mid  := struct { lead : u16, raw : [u8; 2], tail : u16 }
Un   := struct { data : [u8; 3], inner : Mid }
main := fn() -> u64 {
  mut xs : [Elem; 3]
  xs[0] = Elem(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Leaf(a = 20, b = 22))
  xs[1] = Elem(data = [9, 10, 11, 12, 13, 14, 15, 16], inner = Leaf(a = 24, b = 26))
  xs[2] = Elem(data = [17, 18, 19, 20, 21, 22, 23, 24], inner = Leaf(a = 28, b = 30))

  ## the whole element out of the MIDDLE of the array — a wrong stride delivers a neighbour
  e := xs[1]
  if u64(e.data[0]) != 9 { return 1 }
  if u64(e.data[7]) != 16 { return 2 }
  if u64(e.inner.a) != 24 { return 3 }
  if u64(e.inner.b) != 26 { return 4 }

  f := xs[0]
  if u64(f.data[0]) != 1 { return 5 }
  if u64(f.inner.b) != 22 { return 6 }
  g := xs[2]
  if u64(g.data[7]) != 24 { return 7 }
  if u64(g.inner.b) != 30 { return 8 }

  ## the copies are independent of the array and of each other
  xs[1] = Elem(data = [31, 32, 33, 34, 35, 36, 37, 38], inner = Leaf(a = 40, b = 44))
  if u64(e.inner.b) != 26 { return 9 }
  if u64(e.data[0]) != 9 { return 10 }
  if u64(xs[1].inner.b) != 44 { return 11 }
  if u64(f.inner.b) != 22 { return 12 }
  if u64(g.inner.b) != 30 { return 13 }

  ## a whole-element copy back INTO the array from a local
  xs[2] = e
  if u64(xs[2].inner.a) != 24 { return 14 }
  if u64(xs[2].inner.b) != 26 { return 15 }
  if u64(xs[2].data[7]) != 16 { return 16 }
  if u64(xs[1].inner.b) != 44 { return 17 }
  if u64(xs[0].inner.b) != 22 { return 18 }

  ## the same, over the element type whose §6.1 size (10) is NOT a multiple of 8: copying
  ## `struct_words * 8` = 16 bytes would drag in the next element and overrun the destination
  mut u : [Un; 3]
  u[0] = Un(data = [1, 2, 3], inner = Mid(lead = 50, raw = [4, 5], tail = 52))
  u[1] = Un(data = [6, 7, 8], inner = Mid(lead = 54, raw = [9, 10], tail = 56))
  u[2] = Un(data = [11, 12, 13], inner = Mid(lead = 58, raw = [14, 15], tail = 60))
  m := u[1]
  if u64(m.data[0]) != 6 { return 19 }
  if u64(m.data[2]) != 8 { return 20 }
  if u64(m.inner.lead) != 54 { return 21 }
  if u64(m.inner.tail) != 56 { return 22 }
  n := u[2]
  if u64(n.inner.lead) != 58 { return 23 }
  if u64(n.inner.tail) != 60 { return 24 }
  if u64(n.data[2]) != 13 { return 25 }
  ## and the array survived being read
  if u64(u[0].inner.tail) != 52 { return 26 }
  if u64(u[1].inner.tail) != 56 { return 27 }
  if u64(u[2].inner.tail) != 60 { return 28 }
  42
}
