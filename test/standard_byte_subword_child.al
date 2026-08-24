## CLAYOUT S3(b) — THE FENCE S3(a) LEFT, TAKEN DOWN. A standard byte-layout struct holding a
## nested child whose own fields are NARROWER than a machine word. This is the exact program S3(a)
## registered as `reject_standard_byte_subword_child` (this file, renamed): the child was constructed
## two different ways — x86_64 handed it to the WORD-per-field constructor `emit_struct_assign`
## (`inner.b` at byte 16) while aarch64/riscv64/wat recursed through their own byte-precise writer
## (`inner.b` at byte 10) — so no single offset was right on all four and S3(a) made all four refuse.
## S3(b) gives every backend ONE byte-precise whole-value writer whose domain is
## `lower_layout::std_struct_is_byte_writable`, so all four now build the §6.1 image and read it back.
##
## The word model and the C model give DIFFERENT answers here, which is the selection criterion
## (audit §7 risk 4): `inner` is at byte 8 either way, but `b` is at child byte 2 (§6.1) versus child
## byte 8 (one word per field). Note `inner` IS 8-ALIGNED — that is what defeated S3(a)'s
## `(bo / 8) * 8 != bo` guard, which could not see the defect at all because `bo` was 8.
##
## MEASURED, this program's exit code — 42 is correct; each step code below names which comparison
## failed (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime):
##   base 9e0f397                reject /   42 /   42 /   42
##   S3(a) first attempt 4f0c3cb      2 /   42 /   42 /   42   <- x86_64 disagreed with its own three
##   S3(a) as landed 22acca6     reject / trap / trap / trap   (exit 133 / 133 / 134)
##   S3(b), this commit              42 /   42 /   42 /   42
## `struct { a : u32, b : u32 }` and `struct { a : u8, b : u16 }` are covered by
## `standard_byte_subword_child_widths.al`; a child carrying its own byte array, and a child at a
## NON-8-aligned parent offset, by `standard_byte_child_byte_array.al`.
Small := struct { a : u16, b : u16 }
Outer := struct { data : [u8; 8], inner : Small }
main := fn() -> u64 {
  mut o := Outer(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Small(a = 20, b = 22))
  if o.inner.a != 20 { return 1 }
  if o.inner.b != 22 { return 2 }
  if o.data[0] != 1 { return 3 }
  if o.data[7] != 8 { return 4 }
  ## the write side reads back through the same offsets it wrote
  o.inner.b = 33
  if o.inner.b != 33 { return 5 }
  if o.inner.a != 20 { return 6 }
  if o.data[7] != 8 { return 7 }
  ## the whole-child write uses the same writer as the construction
  o.inner = Small(a = 41, b = 39)
  if o.inner.a != 41 { return 8 }
  if o.inner.b != 39 { return 9 }
  if o.data[0] != 1 { return 10 }
  42
}
