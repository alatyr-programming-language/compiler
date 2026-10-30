## IR slice 3n (`docs/ir-slice-4.md` §4): a struct field whose type is a struct or an enum is a
## sub-object at the field's place, built from the shared IR on every twin: a nested literal is built
## in place, `q.inner.x` reads one place deeper, `q.inner = I(…)` and a reassignment of `q` build the
## value first and copy it (so a literal reading `q` sees its old fields, #909/#951), and `match q.c`
## matches the enum sub-object. (2, 1) after the swap, then x + 1: 3 * 10 + 1 + 21 + 34 - 44 = 42.
## (`c = q.c` would also be the IR's to build, but x86_64 drops that field store today — filed as a
## sibling of #465, #958 — so the fixture names the variant directly.)
I := struct { x : i64, y : i64 }
Col := enum { R(u64), G, B(u64, u64) }
Q := struct { inner : I, c : Col, z : i64 }
main := fn() -> u64 {
  mut q := Q(inner = I(x = 1, y = 2), c = Col.B(3, 4), z = 3)
  q = Q(inner = I(x = q.inner.y, y = q.inner.x), c = Col.B(3, 4), z = 21)
  w : u64 = match q.c { Col.R(v) => v; Col.G => 0; Col.B(m, n) => m * 10 + n }
  q.inner = I(x = q.inner.x + 1, y = q.inner.y)
  u64(q.inner.x * 10 + q.inner.y + q.z) + w - 44
}
## expect: run 42
