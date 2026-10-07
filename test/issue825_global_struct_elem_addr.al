## e2e / issue #825 — `ptr(G[i])` of a struct-element array global points at element i.
##
## The address-of path took the word stride (`LABEL + i*8`), so the pointer landed inside an earlier
## element and every read and write through it missed. It now takes the element stride the element
## read and write use (`emit_idx_field_addr`).
##
## 42 means every access agreed. Each miss owns its own code from 100 up.
B := struct { ns : usize, nx : usize, nz : usize }
mut POOL : [B; 4] = [B(ns = 0, nx = 0, nz = 0); 4]
rd := fn(q : ptr(B)) -> usize { deref(q).ns }
main := fn() -> u64 {
  POOL[2] = B(ns = 30, nx = 1, nz = 2)
  p : ptr(mut B) = ptr(mut POOL[2])
  if deref(p).ns != 30 { return 100 }
  deref(p).nz = 9
  if POOL[2].nz != 9 { return 101 }
  if POOL[1].nz != 0 or POOL[3].ns != 0 { return 102 }
  if rd(ptr(POOL[2])) != 30 { return 103 }
  u64(deref(p).ns + POOL[2].nz + deref(p).nx + 2)
}
