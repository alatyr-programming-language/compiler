## Types §9.4 — inner index into an ARRAY FIELD of an array-of-struct element `xs[i].arr[j]`. The
## `pad` field gives a non-zero field offset so a mis-composed (element base + field offset + inner
## index) address is exposed. Was a SILENT MISCOMPILE (base is a `Field`, not a `Var`, so the index
## read used slot 0 → 0). Reads across both elements + both indices. 110 = success.
S := struct { pad : u64, arr : [u64; 3] }
main := fn() -> u64 {
  mut xs : [S; 2]
  xs[0] = S(pad = 9, arr = [10, 20, 30])
  xs[1] = S(pad = 8, arr = [40, 50, 60])
  u64(xs[0].arr[0] + xs[0].arr[1] + xs[0].arr[2] + xs[1].arr[1])
}
