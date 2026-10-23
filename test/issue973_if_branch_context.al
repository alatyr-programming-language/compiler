## e2e (#973 — Types §2.3 / Functions §1.4: the type an `if` has in value position is the CONTEXT of
## its branches; a declared type reaches the expression in that position, it is not re-derived from it).
## `ib_bx_if` built each branch with `ib_bx`, which asks the expression its OWN type. The bare literal
## branch `else { 1000 }` has none — `VcLit`, no context having reached it — so the branch refused,
## `g13` was refused as `sema-gap literal: expr Num` at the `1000`, and the function fell back to a
## LEGACY emitter. There the value went wrong, silently, on aarch64 and riscv64: the legacy path builds
## an aggregate literal in argument position into the SAME frame slot as the nested call's own aggregate,
## so `g8`'s `p11.k1` — which this program sets to 1 and never changes — read the inner literal's first
## word instead:
##   str x0,[x29,#64]   outer S2 k1 = 1
##   str x0,[x29,#64]   the INNER S2(k1 = p15.k3, …) reuses the slot — k1 clobbered
##   bl  g8             returns p11.k1 = p15.k3, not 1
## Progen seed 2074800535, reduced by the nightly reducer and then by machine (line- and subexpression-
## level delta debugging; hand-narrowing does NOT reproduce, the shape needs the whole set of temporaries).
## NON-VACUOUS: before the fix aarch64 and riscv64 answer **3 where 2 is due**, x86_64 and wasm answer
## 2 — a quiet wrong value, no diagnostic. `check_ir_built` below also pins that `g13` is BUILT by the
## shared IR, so re-opening the gap shows up as a refusal rather than as a wrong number.
## Values: g8 returns p11.k1; every S2 it is handed has k1 = 1, so g8 = 1. g13 = g8(…) = 1 (the v16
## statement's value is discarded, and the nested g3 returns its third argument, 1). g17 = g3(…,…,g13)
## = 1. acc = (0 * 31) ^ 1 = 1; r = 1 % 113 = 1; return 2.
S1 := struct { k1 : i64, k2 : i64, k3 : i64, k4 : i64 }
S2 := struct { k1 : i64, k2 : i64, k3 : i64 }
g3 := fn(p4 : S2, p5 : S2, p6 : i64) -> i64 {
  return p6
}
g8 := fn(p9 : i64, p10 : i64, p11 : S2) -> i64 {
  return g3(p11, p11, p11.k1)
}
g13 := fn(p14 : S1, p15 : S1) -> i64 {
  mut v16 : i64 = g8((if (0 - 2) != 3 { p15.k1 } else { 1000 }), 1, S2(k1 = 1, k2 = 1, k3 = 2))
  return g8(1, 1, S2(k1 = 1, k2 = 1, k3 = g3(S2(k1 = p15.k3, k2 = 1, k3 = 1), S2(k1 = 1, k2 = 1, k3 = 1), 1)))
}
g17 := fn(p18 : i64) -> i64 {
  mut v19 : i64 = g8(1, 1, S2(k1 = p18, k2 = 1, k3 = 1))
  return g3(S2(k1 = 1, k2 = 1, k3 = 1), S2(k1 = 1, k2 = 1, k3 = 1), g13(S1(k1 = 1, k2 = v19, k3 = p18, k4 = p18), S1(k1 = v19, k2 = p18, k3 = v19, k4 = p18)))
}
main := fn() -> u64 {
  mut acc : i64 = 0
  acc = unchecked ((acc * 31) ^ g17(3))
  mut r : i64 = acc % 113
  if r < 0 { r = r + 113 }
  return u64(r) + 1
}
