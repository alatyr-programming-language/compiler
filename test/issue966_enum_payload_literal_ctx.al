## e2e (#966, #968 — Types §2.3: a declared type is the CONTEXT of the expression in that position).
## An enum construction's declared payload types are the context of its arguments, exactly as a call's
## parameter types already are (`sema_vty_call_args`). Without it a literal-only payload argument
## (`E1.V2(1, unchecked (7 ^ 0))`) records no type of its own (`VcLit`), the builder reports
## `sema-gap literal: expr Num`, and the whole function falls back to the legacy emitter — which builds
## an aggregate in expression position through the single global `$__tmp` and yields the INNER block's
## address when a nested construction clobbers it (#967): wasm answered 97 where 2 is due
## (progen seed 2074803566). Closing the context removes the fallback, and with it the wrong value.
## Values: ef8 returns V4, whose arm is 1; acc = (0*31)^1 = 1; (1 % 113) + 1 = 2.
E1 := enum { V1, V2(u64, u64), V3, V4(u64, u64, u64) }
g2 := fn(p3 : E1, p4 : E1) -> u64 { return 1 }
ef8 := fn(p9 : E1) -> E1 {
  mut v10 : u64 = g2(E1.V2(1, unchecked (7 ^ 0)), E1.V3)
  return E1.V4(1, 1, g2(p9, E1.V2(1, 1)))
}
main := fn() -> u64 {
  mut acc : u64 = 0
  acc = unchecked ((acc * 31) ^ (match ef8(E1.V3) { E1::V1 => { 1000 } E1::V2(m13, m14) => { 1000 } E1::V3 => { 4611686018427387907 } E1::V4(m15, m16, m17) => { 1 } }))
  if acc != 1 { return 100 + acc }
  return (acc % 113) + 1
}
