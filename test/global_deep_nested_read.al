## DEPTH-3 nested-field read of a mutable-global struct (`STATE.i1.i2.c`). global_place
## resolves the cumulative .data offset recursively through the whole chain; a scalar final field is a
## single-word read. 20 + 10 + 7 + 5 = 42.
C := struct { c : u64, d : u64 }
B := struct { i2 : C, m : u64 }
A := struct { i1 : B, n : u64 }
mut STATE := A(i1 = B(i2 = C(c = 20, d = 10), m = 7), n = 5)
main := fn() -> u64 { return STATE.i1.i2.c + STATE.i1.i2.d + STATE.i1.m + STATE.n }
