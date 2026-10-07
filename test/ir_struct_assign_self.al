## IR slice 3a (`docs/ir-slice-3.md` §1, #909): `p = P(a = p.b, b = p.a)` assigns the VALUE of the
## literal, `(2, 1)`. The shared IR builds every aggregate value in its own frame object and copies it
## into the destination (`docs/ir.md` §3.3), so the IR-selected aarch64/riscv64 answer 21. x86_64 and
## the legacy emitters build the literal in place, so its second initializer reads the field its first
## one overwrote: x86_64 22, wasm 0 (#909, open).
P := struct { a : i64, b : i64 }
main := fn() -> u64 {
  mut p := P(a = 1, b = 2)
  p = P(a = p.b, b = p.a)
  u64(p.a * 10 + p.b)
}
