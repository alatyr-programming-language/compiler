## Types §9.4 — nested SCALAR field WRITE THROUGH a pointer `deref(p).b.pb = v` / `deref(p).b.c.cx = v`
## (depth>=2), then read back the mutated struct. Was a SILENT NO-OP (`field_slot` -1 → a store to
## `-0(%rbp)` corrupting the frame pointer + dropping the write). 91 = success (77 + 3 + 11).
C := struct { cx : u64, cy : u64 }
B := struct { pb : u64, c : C }
A := struct { pa : u64, b : B, tail : u64 }
main := fn() -> u64 {
  mut a := A(pa = 11, b = B(pb = 22, c = C(cx = 5, cy = 30)), tail = 7)
  p := ptr(mut a)
  deref(p).b.pb = 77
  deref(p).b.c.cx = 3
  u64(a.b.pb + a.b.c.cx + a.pa)
}
