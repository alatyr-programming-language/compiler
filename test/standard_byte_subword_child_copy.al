## CLAYOUT S3(c) — THE BYTE-PRECISE WHOLE-VALUE COPIER, the mirror of S3(b)'s writer. This file was
## `reject_standard_byte_subword_child_copy.al`: S3(b) made a SUB-WORD nested child constructible and
## thereby put a byte-precise 4-byte child in front of the whole-value EXTRACT `copy := o.inner` for the
## first time. That extract was `struct_words` whole WORDS into a destination local read back at WORD
## offsets, so `copy.a` read 0 — a WRONG VALUE where the pre-S3(b) compiler trapped, which I11 forbids,
## and it was fenced rather than shipped.
##
## The copy is not a memcpy: the SOURCE is the child's §6.1 byte image inside the root, the DESTINATION
## is a standalone local read in the tier `layout_kind` gives the child's own type — one machine word per
## field for every struct here, since none of them carries a byte array. So each scalar leaf moves from
## its §6.1 byte to its destination WORD, sign-extended from the field's own width for an `iN`.
## `lower_layout::std_copy_kind` decides that once for all four backends; `emit_standard_copy` /
## `a64_std_copy` / `rv_std_copy` / `wat_std_copy` only spell the moves.
##
## The selection criterion (audit §7 risk 4): every child here is one whose WORD image and §6.1 image
## DISAGREE, so a green run cannot be a coincidence — `b` sits at byte 2/4/2/2 and at word 1 = byte 8.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   base 04b221d               reject / 133 / 133 / 134   (the S3(b) copy fence)
##   S3(b) writer, no fence     reject /   1 /   1 /   1   <- `copy.a` read 0: the wrong value I11 forbids
##   S3(c), this commit             42 /  42 /  42 /  42
## Every comparison is INSIDE the program and each failure returns its own step code (exit codes
## truncate mod 256, and all four backends must agree on the same 42).
Small  := struct { a : u16, b : u16 }
Wide   := struct { a : u32, b : u32 }
Mixed  := struct { a : u8,  b : u16 }
Signed := struct { a : i8,  b : i16 }
Deep   := struct { lo : u16, inner : Small }

O1 := struct { data : [u8; 8], inner : Small }
O2 := struct { data : [u8; 8], inner : Wide }
O3 := struct { data : [u8; 4], inner : Mixed }
O4 := struct { data : [u8; 3], inner : Signed }
O5 := struct { data : [u8; 8], mid : Deep }

main := fn() -> u64 {
  ## u16 + u16 — the shape the fence named. Source bytes 8 and 10; destination words 0 and 1.
  mut o1 := O1(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Small(a = 20, b = 22))
  c1 := o1.inner
  if u64(c1.a) != 20 { return 1 }
  if u64(c1.b) != 22 { return 2 }

  ## u32 + u32 — a 4-byte leaf, so the load must be `movl`/`ldr w0`/`lwu`/`i64.load32_u`, not a word.
  mut o2 := O2(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Wide(a = 70000, b = 80000))
  c2 := o2.inner
  if u64(c2.a) != 70000 { return 3 }
  if u64(c2.b) != 80000 { return 4 }

  ## u8 + u16 — `b` is 2-ALIGNED, so §6.1 pads one byte after `a`: the leaf is at child byte 2, not 1.
  mut o3 := O3(data = [1, 2, 3, 4], inner = Mixed(a = 200, b = 40000))
  c3 := o3.inner
  if u64(c3.a) != 200 { return 5 }
  if u64(c3.b) != 40000 { return 6 }

  ## i8 + i16 — SIGNED leaves: the copy must sign-extend from the field's OWN width before it stores a
  ## whole word, or a negative value reads back as a large positive one.
  mut o4 := O4(data = [1, 2, 3], inner = Signed(a = 0 - 3, b = 0 - 300))
  c4 := o4.inner
  if i64(c4.a) != 0 - 3 { return 7 }
  if i64(c4.b) != 0 - 300 { return 8 }

  ## TWO DEEP — the copied child itself has a struct field, so the plan recurses: `inner.b` is at
  ## source byte 8+8+2 = 18 and at destination word 1+1 = 2.
  mut o5 := O5(data = [1, 2, 3, 4, 5, 6, 7, 8], mid = Deep(lo = 11, inner = Small(a = 13, b = 17)))
  c5 := o5.mid
  if u64(c5.lo) != 11 { return 9 }
  if u64(c5.inner.a) != 13 { return 10 }
  if u64(c5.inner.b) != 17 { return 11 }

  ## The ROOTS must still read correctly after their children were copied out (a copy must not write
  ## back into its source).
  if u64(o1.inner.b) != 22 { return 12 }
  if u64(o3.data[3]) != 4 { return 13 }
  if u64(o5.mid.inner.b) != 17 { return 14 }

  ## Re-read every earlier copy LAST, so an overlapping destination cannot hide behind the order the
  ## checks happen to run in.
  if u64(c1.b) != 22 { return 15 }
  if u64(c2.b) != 80000 { return 16 }
  if u64(c3.b) != 40000 { return 17 }
  if i64(c4.b) != 0 - 300 { return 18 }
  42
}
