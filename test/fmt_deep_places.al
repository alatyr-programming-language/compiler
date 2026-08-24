## §5 fmt — the DEEP aggregate place family plus the two aggregate FIELD types, none of which fmt had
## ever seen. The silent miscompile locked here is the NO-INITIALIZER local `mut xs : [A; 2]`: it is an
## ordinary `Stmt.Assign` carrying a placeholder value, so fmt re-emitted it as `mut xs : [A; 2] = 0` —
## a different program (this fixture ran 65 before the reformat and 1 after). Also covered: a `Slice(T)`
## field, a `[Struct; N]` field, and the deep places `xs[i].b.c.cx` / `xs[i].arr[j]`, READ and WRITTEN.
##   xs[0].b.c.cx 20 (written) + xs[1].arr[1] 30 (written) + xs[0].arr[0] 5 + xs[1].b.c.cy 10
##   + t.ps[0].x 1 + t.ps[1].y 4 + sa.v.len 4 + sa.n 5 = 79
C := struct {
  cx : u64,
  cy : u64,
}

B := struct {
  pb : u64,
  c : C,
}

A := struct {
  pa : u64,
  b : B,
  arr : [u64; 2],
}

P := struct {
  x : u64,
  y : u64,
}

T := struct {
  ps : [P; 2],
  n : u64,
}

SA := struct {
  v : Slice(u64),
  n : u64,
}

main := fn() -> u64 {
  mut xs : [A; 2]
  xs[0] = A(pa = 1, b = B(pb = 2, c = C(cx = 3, cy = 4)), arr = [5, 6])
  xs[1] = A(pa = 7, b = B(pb = 8, c = C(cx = 9, cy = 10)), arr = [11, 12])
  xs[0].b.c.cx = 20
  xs[1].arr[1] = 30
  t := T(ps = [P(x = 1, y = 2), P(x = 3, y = 4)], n = 5)
  ys := [1, 2, 3, 4]
  sa := SA(v = ys[0..4], n = 5)
  return xs[0].b.c.cx + xs[1].arr[1] + xs[0].arr[0] + xs[1].b.c.cy + t.ps[0].x + t.ps[1].y + u64(sa.v.len) + sa.n
}
