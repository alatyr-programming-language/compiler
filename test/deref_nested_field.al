## Types §9.4 — nested SCALAR field READ THROUGH a pointer `deref(p).b.c.cx` (depth>=2). Reads
## every field via the pointer so a mis-composed pointee word offset is exposed. Was a SILENT
## MISCOMPILE (`field_slot` returned -1 for a `Field(Deref(...))` base → `pushq $0`). 75 = success.
C := struct { cx : u64, cy : u64 }
B := struct { pb : u64, c : C }
A := struct { pa : u64, b : B, tail : u64 }
main := fn() -> u64 {
  mut a := A(pa = 11, b = B(pb = 22, c = C(cx = 5, cy = 30)), tail = 7)
  p := ptr(mut a)
  u64(deref(p).pa + deref(p).b.pb + deref(p).b.c.cx + deref(p).b.c.cy + deref(p).tail)
}
