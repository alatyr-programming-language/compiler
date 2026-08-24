## CLAYOUT S3(c) — the IMAGE half of the byte-precise copier. When the copied child carries its OWN
## byte-typed array it is BYTE-tier in its own right (`layout_kind` says so precisely because of that
## field), so its destination local is read at §6.1 offsets — the same offsets the source holds. The
## copy is then the child's `standard_struct_bytes` bytes moved VERBATIM, and it has to be byte-wise:
## `Mid` is 6 bytes, so any wider load would read past it and any wider store would write past it.
##
## Both parent offsets are covered, and they are chosen so the word model and §6.1 disagree:
##   `Un` puts `inner` at byte 4 — NOT 8-aligned, because a child of `u16`/`[u8;2]` fields has a real
##        §6.1 alignment of 2. The word model has no such offset at all.
##   `Al` puts `inner` at byte 8, which is the case that defeated S3(a)'s `(bo/8)*8 != bo` guard.
##
## MEASURED exit code (x86_64 / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   base 04b221d   reject / 133 / 133 / 134   (the S3(b) copy fence; x86_64 a located panic)
##   S3(c)              42 /  42 /  42 /  42
Mid := struct { lead : u16, raw : [u8; 2], tail : u16 }
Un  := struct { data : [u8; 3], inner : Mid }
Al  := struct { data : [u8; 8], inner : Mid }

main := fn() -> u64 {
  ## the child at a NON-8-aligned parent offset (byte 4)
  mut u := Un(data = [1, 2, 3], inner = Mid(lead = 20, raw = [7, 9], tail = 22))
  cu := u.inner
  if u64(cu.lead) != 20 { return 1 }
  if u64(cu.raw[0]) != 7 { return 2 }
  if u64(cu.raw[1]) != 9 { return 3 }
  if u64(cu.tail) != 22 { return 4 }

  ## the same child at an 8-aligned parent offset (byte 8)
  mut al := Al(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Mid(lead = 30, raw = [11, 13], tail = 33))
  ca := al.inner
  if u64(ca.lead) != 30 { return 5 }
  if u64(ca.raw[0]) != 11 { return 6 }
  if u64(ca.raw[1]) != 13 { return 7 }
  if u64(ca.tail) != 33 { return 8 }

  ## the sources are untouched by their own copies
  if u64(u.inner.tail) != 22 { return 9 }
  if u64(u.data[2]) != 3 { return 10 }
  if u64(al.inner.tail) != 33 { return 11 }
  ## and the two copies do not overlap each other
  if u64(cu.lead) != 20 { return 12 }
  if u64(ca.raw[1]) != 13 { return 13 }
  42
}
