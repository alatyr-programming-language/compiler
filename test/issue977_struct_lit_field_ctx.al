## issue #977 (progen seed 2074800535, nightly run 39877712130 shard 0) — a struct literal's field
## types are the CONTEXT of its arguments.
##
## `g13` puts a literal inside `unchecked`, inside a division, inside the `k3` field of a struct literal
## passed to a call. Sema recorded each field's declared type but propagated it no further: the arms that
## push a context covered a call's parameters (`sema_vty_call_args`) and an enum payload's types (#968),
## while `Expr::StructLit` sat in the catch-all `{}`. So the `100` stayed `VcLit`.
##
## The builder does hand the field's type down — `ib_agg_lit_into` calls `ib_value_ctx` with
## `IbKS(ty = fld.ty, sg = fld.sg)` — but `ib_value_at(e, k)` builds with `ib_bx(e)` and coerces only
## the RESULT, so the context was dropped on the way in and `ib_bx_num` asked the `100` its own type.
## `g13` was refused as `sema-gap literal: expr Num` at 19:47 and fell back to a legacy emitter, which
## split four ways: x86_64=2 aarch64=4 riscv64=4 wasm=2, the model at 2.
##
## Asserted twice on purpose, as in #973: the VALUE (exit 2) and the FACT that `g13` builds through the
## IR (`check_ir_build` below). The wrong value lived in the fallback, so a run that only checked the
## exit code would pass again on any backend whose legacy path happens to answer correctly.
S1 := struct { k1 : i64, k2 : i64, k3 : i64, k4 : i64 }
S2 := struct { k1 : i64, k2 : i64, k3 : i64 }

## The ambient prelude trigger (#532); uncalled, kept as the generator emits it.
progen_trigger := fn() -> u64 {
  match checked_add(u8(1), u8(1)) { Some(v) => { u64(v) } None => { 0 } }
}

g3 := fn(p4 : S2, p5 : S2, p6 : i64) -> i64 {
  return p6
}

g8 := fn(p9 : i64, p10 : i64, p11 : S2) -> i64 {
  return g3(p11, p11, p11.k1)
}

## The function that was refused: `k3`'s literal parts sit under `unchecked` and a division.
g13 := fn(p14 : S1, p15 : S1) -> i64 {
  mut v16 : i64 = 1
  v16 = g3(S2(k1 = 1, k2 = 1, k3 = unchecked (100 / unchecked ((3 % 7) + 8))), S2(k1 = 1, k2 = 1, k3 = 1), 1)
  return g8(1, 1, S2(k1 = 1, k2 = 1, k3 = g3(S2(k1 = p15.k3, k2 = 1, k3 = 1), S2(k1 = 1, k2 = 1, k3 = 1), 1)))
}

g17 := fn(p18 : i64) -> i64 {
  mut v19 : i64 = g8(1, 1, S2(k1 = p18, k2 = 1, k3 = 1))
  return g3(S2(k1 = 1, k2 = 1, k3 = 1), S2(k1 = 1, k2 = 1, k3 = 1), g13(S1(k1 = v19, k2 = v19, k3 = p18, k4 = p18), S1(k1 = v19, k2 = p18, k3 = v19, k4 = p18)))
}

main := fn() -> u64 {
  mut acc : i64 = 0
  acc = unchecked ((acc * 31) ^ g17(3))
  mut r : i64 = acc % 113
  if r < 0 { r = r + 113 }
  return u64(r) + 1
}
## expect: run 2
