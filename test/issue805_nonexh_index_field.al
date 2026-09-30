## Issue #805 / Control Flow §5.1 — an element of a struct FIELD array, `h.arr[i]` with
## `arr : [C; 2]`. `B` is uncovered and no `_` default is present; the parent built it and bound `r`
## to 0 for `h.arr[0] = C.B`.
C := enum { R, G, B }
H := struct { arr : [C; 2] }
main := fn() -> u64 {
  h := H(arr = [C.B, C.G])
  r := match h.arr[0] { R => { 11 }; G => { 22 } }
  return r
}
