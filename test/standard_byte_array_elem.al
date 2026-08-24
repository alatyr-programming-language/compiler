## CLAYOUT S3(d) — THE ARRAY-ELEMENT TIER. The exact program the measured as the family's
## last silent wrong value: `mut xs : [Elem; 3]` with NO literal initializer, each element written by
## `xs[k] = Elem(…)`, then every element and every field read back.
##
## Layout, per Types §6.1/§6.4 (declaration order, natural alignment, standard padding; array stride =
## element size rounded up to element alignment):
##   Leaf { a : u16, b : u16 }              §6.1 offsets 0, 2      word offsets 0, 8
##   Elem { data : [u8; 8], inner : Leaf }  §6.1 offsets 0, 8      size 24, align 8   stride 24
## `inner` occupies 16 bytes because a non-byte-tier child still reports `standard_type_byte_size` =
## `struct_words * 8` in this stage, so the stride here happens to equal `struct_words * 8`. That is
## deliberate: it isolates the WRITE and the PLACE from the stride. The shapes where the byte stride
## and `struct_words * 8` DISAGREE are `standard_byte_array_elem_unaligned.al` (10 vs 16).
##
## Why it was wrong, measured: the element is written one machine WORD per field — ten words = 80
## bytes for this Elem — into a 24-byte stride, so element 1's write walks over element 0. An earlier
## 2-element probe answered 42 by coincidence, depending on which bytes it read; three elements with
## every field read falsifies it.
##
## Every comparison is INSIDE the program (exit codes truncate mod 256) and every value is < 126.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   pre-fence (495e842)              2 /      2 /      2 /      2   <- WRONG on all four
##   S3(c) as landed (dd10312)   reject / reject / reject / reject
##   S3(d), this commit              42 / reject / reject / reject
## The three cross backends keep `lower_layout::require_no_byte_layout_array_elem`: their element
## addressing is word-denominated at a different set of sites, and a per-backend fence is acceptable
## where a wrong value is not (I11).
Leaf := struct { a : u16, b : u16 }
Elem := struct { data : [u8; 8], inner : Leaf }
main := fn() -> u64 {
  mut xs : [Elem; 3]
  xs[0] = Elem(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Leaf(a = 20, b = 22))
  xs[1] = Elem(data = [9, 9, 9, 9, 9, 9, 9, 9], inner = Leaf(a = 30, b = 33))
  xs[2] = Elem(data = [7, 7, 7, 7, 7, 7, 7, 7], inner = Leaf(a = 40, b = 44))

  ## every element, every field — element 0 first, so an element-1 write that walked over it shows up
  if u64(xs[0].data[0]) != 1 { return 1 }
  if u64(xs[0].data[2]) != 3 { return 2 }
  if u64(xs[0].data[7]) != 8 { return 3 }
  if u64(xs[0].inner.a) != 20 { return 4 }
  if u64(xs[0].inner.b) != 22 { return 5 }

  if u64(xs[1].data[0]) != 9 { return 6 }
  if u64(xs[1].data[7]) != 9 { return 7 }
  if u64(xs[1].inner.a) != 30 { return 8 }
  if u64(xs[1].inner.b) != 33 { return 9 }

  if u64(xs[2].data[0]) != 7 { return 10 }
  if u64(xs[2].data[7]) != 7 { return 11 }
  if u64(xs[2].inner.a) != 40 { return 12 }
  if u64(xs[2].inner.b) != 44 { return 13 }

  ## THE ALIASING CHECK the stride bug broke: rewrite the MIDDLE element, then read its neighbours.
  xs[1] = Elem(data = [11, 12, 13, 14, 15, 16, 17, 18], inner = Leaf(a = 50, b = 55))
  if u64(xs[1].inner.b) != 55 { return 14 }
  if u64(xs[1].data[3]) != 14 { return 15 }
  if u64(xs[0].inner.b) != 22 { return 16 }      ## element k-1 untouched
  if u64(xs[0].data[7]) != 8 { return 17 }
  if u64(xs[2].inner.b) != 44 { return 18 }      ## element k+1 untouched
  if u64(xs[2].data[0]) != 7 { return 19 }

  ## a NESTED scalar STORE through the element place, not only reads
  xs[2].inner.b = 61
  if u64(xs[2].inner.b) != 61 { return 20 }
  if u64(xs[2].inner.a) != 40 { return 21 }      ## its sibling field survived
  if u64(xs[2].data[7]) != 7 { return 22 }       ## the byte array survived
  if u64(xs[1].inner.b) != 55 { return 23 }      ## the neighbour survived

  ## a DEPTH-1 byte-array element STORE through the element place
  xs[0].data[2] = 99
  if u64(xs[0].data[2]) != 99 { return 24 }
  if u64(xs[0].data[1]) != 2 { return 25 }
  if u64(xs[0].data[3]) != 4 { return 26 }
  if u64(xs[0].inner.b) != 22 { return 27 }

  ## a runtime (non-constant) index must resolve the same place
  mut i := 0
  mut acc := 0
  while i < 3 {
    acc = acc + u64(xs[i].inner.a)
    i = i + 1
  }
  if acc != 20 + 50 + 40 { return 28 }
  42
}
