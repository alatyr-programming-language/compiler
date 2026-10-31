## IR slice 3a (`docs/ir-slice-3.md` §1, #909): `p = P(a = p.b, b = p.a)` assigns the VALUE of the
## literal, `(2, 1)`. The shared IR builds every aggregate value in its own frame object and copies it
## into the destination (`docs/ir.md` §3.3), so the IR-selected twins answer 21. x86_64 built the
## literal in place, so its second initializer read the field its first one overwrote and answered 22
## (#909); it now builds a literal that may read its own destination in a temp block and copies it.
P := struct { a : i64, b : i64 }
main := fn() -> u64 {
  mut p := P(a = 1, b = 2)
  p = P(a = p.b, b = p.a)
  u64(p.a * 10 + p.b)
}
## expect: run 21
