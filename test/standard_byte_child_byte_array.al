## CLAYOUT S3(b) — a nested child that carries ITS OWN byte array, at an ALIGNED and at a
## NON-8-ALIGNED parent offset. Both halves matter and neither was reachable before:
##
##  * a child holding a byte array is itself in the BYTE tier (`layout_kind` 2), which S3(a)'s
##    `layout_struct_is_word_stored` refused outright — it has no word image at all.
##  * because such a child has a real §6.1 ALIGNMENT (2 here, not the flat 8 a non-byte aggregate
##    still reports), the parent can place it at byte 4. That is the first nested child in the corpus
##    at a non-8-aligned offset, and it is what proves the writer stores at ARBITRARY byte offsets
##    rather than at whole slots — S3(a)'s `(bo / 8) * 8 != bo` guard rejected exactly this.
##
## Layout, per Types §6.1 (declaration order, natural alignment, standard padding):
##   Mid  { lead : u16, raw : [u8; 2], tail : u16 }   offsets 0, 2, 4   size 6   align 2
##   Un   { data : [u8; 3], inner : Mid }             offsets 0, 4                  <- inner at 4
##   Al   { data : [u8; 8], inner : Mid }             offsets 0, 8                  <- inner at 8
## `raw` is written between `lead` and `tail`, so a raw store landing at the wrong offset shows up as
## a wrong `lead` or `tail` — the array's own elements are not directly readable through a nested
## path in this slice, and this is the check that stands in for reading them.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime):
##   S3(a) as landed 22acca6     reject / trap / trap / trap
##   S3(b), this commit              42 /   42 /   42 /   42
Mid := struct { lead : u16, raw : [u8; 2], tail : u16 }
Un := struct { data : [u8; 3], inner : Mid }
Al := struct { data : [u8; 8], inner : Mid }
main := fn() -> u64 {
  mut u := Un(data = [1, 2, 3], inner = Mid(lead = 20, raw = [4, 5], tail = 22))
  if u.inner.lead != 20 { return 1 }
  if u.inner.tail != 22 { return 2 }
  if u.data[0] != 1 { return 3 }
  if u.data[2] != 3 { return 4 }

  mut a := Al(data = [6, 7, 8, 9, 10, 11, 12, 13], inner = Mid(lead = 24, raw = [14, 15], tail = 26))
  if a.inner.lead != 24 { return 5 }
  if a.inner.tail != 26 { return 6 }
  if a.data[0] != 6 { return 7 }
  if a.data[7] != 13 { return 8 }

  ## the scalar leaf write goes through the same accumulated byte offset as the read
  u.inner.tail = 28
  if u.inner.tail != 28 { return 9 }
  if u.inner.lead != 20 { return 10 }
  if u.data[2] != 3 { return 11 }

  ## and the unaligned local was not disturbed by the aligned one
  if a.inner.lead != 24 { return 12 }
  42
}
