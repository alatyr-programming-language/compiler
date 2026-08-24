## P1-CLAYOUT S3(c) — `xs[i].inner.leaf` through a STANDARD BYTE-LAYOUT element struct.
##
## S3(d) UPDATE: this is now a located reject on the THREE CROSS BACKENDS ONLY. x86_64 composes the
## place correctly (byte-precise element stride + `layout_field_offset_bytes` per hop) and returns 42,
## so the `build_reject_has` line that gated x86 is gone and the three `emit_reject_has` lines remain.
## The x86_64 coverage for exactly this program moved to `standard_byte_array_elem_word_child.al`
## (same declarations, three elements, every field, plus the stride assertion), so this file's name
## keeps meaning what it says on the backends that still refuse. Everything below is the S3(c) record.
##
## The cause: the element is written at its §6.1 byte offsets (`inner` at byte 8 for
## `struct { data : [u8;4], inner }`) while `resolve_idx_field_place` composes WORD offsets
## (`field_word_offset` counts `[u8;4]` as FOUR WORDS, putting `inner` at byte 32). The two name places
## 24 bytes apart. `standard_field_path` already refuses an `Index` root for exactly this reason.
##
## And on the three cross backends it was worse than a bad read: each element is written one machine WORD
## per field into a stride of `struct_words * 8`, so for `struct { data : [u8;8], inner : { a, b : u16 } }`
## the write is ten words = 80 bytes into a 24-byte stride and element 1 walks over element 0. Measured on
## 04b221d: a 3-element array read back byte by byte returned exit 1 on aarch64, riscv64 AND wasm — and
## the 2-element `xs[i].data[j]` variant returned 42 only because of WHICH bytes it happened to read.
## S3(c) therefore refuses an array whose ELEMENT is a byte-layout struct on those three backends
## (`lower_layout::require_no_byte_layout_array_elem`, called from the one element-width query each of
## them funnels every array through), which is what closes the last I11 violation in this family.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   base 495e842 (pre-S3(b))         1 /      1 /      1 /      1   <- wrong on ALL FOUR
##   04b221d (S3(b))             reject /      1 /      1 /      1   <- x86_64 fenced, the three not
##   S3(c), this commit          reject / reject / reject / reject
## Giving the array-element tier a byte-precise STRIDE and place resolver is the next slice; until then a
## trap is acceptable and a wrong value is not.
Inner := struct { x : u64, y : u64 }
Outer := struct { data : [u8; 4], inner : Inner }
main := fn() -> u64 {
  mut xs : [Outer; 2]
  xs[0] = Outer(data = [1, 2, 3, 4], inner = Inner(x = 20, y = 22))
  xs[1] = Outer(data = [5, 6, 7, 8], inner = Inner(x = 24, y = 26))
  if xs[0].inner.y != 22 { return 1 }
  if xs[1].inner.y != 26 { return 2 }
  42
}
