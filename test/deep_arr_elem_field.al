## Types §9.4 — DEEP fixed-array element nested-field READ `xs[i].b.c.cx` (depth-3+ field chain
## off an array-of-struct element). `pad`/leading fields give non-zero word offsets so a mis-
## composed offset is exposed. Sums leaf reads across BOTH elements (index scaling + composed
## field offset). Was a SILENT MISCOMPILE (deep chain fell to `pushq $0` → read 0). 42 = success.
C := struct { cx : u64, cy : u64 }
B := struct { pb : u64, c : C }
A := struct { pa : u64, b : B, tail : u64 }
main := fn() -> u64 {
  mut xs : [A; 2]
  xs[0] = A(pa = 11, b = B(pb = 22, c = C(cx = 5, cy = 30)), tail = 7)
  xs[1] = A(pa = 1, b = B(pb = 2, c = C(cx = 3, cy = 4)), tail = 9)
  u64(xs[0].b.c.cx + xs[0].b.c.cy + xs[1].b.c.cx + xs[1].b.c.cy)
}
