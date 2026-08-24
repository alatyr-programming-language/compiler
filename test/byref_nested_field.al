## Types §9.4 — nested SCALAR field READ off a BY-REF struct PARAM `a.b.c.cx` (depth>=2). A by-ref
## param slot holds a POINTER to the caller's struct; the depth>=2 walk must load through it. Was a
## SILENT MISCOMPILE (`field_slot`'s Var arm computed `ent.off - fi` off the pointer slot). 75 = ok.
C := struct { cx : u64, cy : u64 }
B := struct { pb : u64, c : C }
A := struct { pa : u64, b : B, tail : u64 }
readsum := fn(a : A) -> u64 { a.pa + a.b.pb + a.b.c.cx + a.b.c.cy + a.tail }
main := fn() -> u64 {
  a := A(pa = 11, b = B(pb = 22, c = C(cx = 5, cy = 30)), tail = 7)
  u64(readsum(a))
}
