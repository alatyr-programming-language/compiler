## ROADMAP §4: DEPTH-3 nested scalar-field WRITE of a mutable-global struct (`STATE.i1.i2.c = v`),
## then read back. global_place resolves the cumulative offset for the FieldPathAssign store. 20+10+7+5=42.
C := struct { c : u64, d : u64 }
B := struct { i2 : C, m : u64 }
A := struct { i1 : B, n : u64 }
mut STATE := A(i1 = B(i2 = C(c = 1, d = 1), m = 1), n = 5)
main := fn() -> u64 {
  STATE.i1.i2.c = 20
  STATE.i1.i2.d = 10
  STATE.i1.m = 7
  return STATE.i1.i2.c + STATE.i1.i2.d + STATE.i1.m + STATE.n
}
