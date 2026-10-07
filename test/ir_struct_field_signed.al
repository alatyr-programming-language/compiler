## IR slice 3a (`docs/ir-slice-3.md` §1, #765): a struct local is a frame object, and a field read is
## a `load` at the field's declared type, so a signed `i64` field divides and orders SIGNED. On the
## legacy twin emitters each shape below divided unsigned (aarch64/riscv64/wasm answered 1). x86_64 and
## the IR-selected register twins answer 42; wasm keeps its legacy emission until frame objects have
## the shadow stack (`docs/ir-slice-3.md` §3.5), so its row stays the #765 value.
S := struct { k : i64, m : i64 }
main := fn() -> u64 {
  s := S(k = 0 - 100, m = 3)
  q : i64 = s.k / 9
  r : i64 = s.k % 9
  t : i64 = (0 - 7) / s.m
  u : i64 = unchecked ((0 - 7) % s.m)
  mut ok : u64 = 0
  if q == 0 - 11 { ok = ok + 10 }
  if r == 0 - 1 { ok = ok + 10 }
  if t == 0 - 2 { ok = ok + 10 }
  if u == 0 - 1 { ok = ok + 10 }
  if s.k < 0 { ok = ok + 2 }
  ok
}
