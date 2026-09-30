## Checked NARROW-WIDTH overflow trap through an INDEX-READ BINDING (I11 / CG-6): `x := xs[i]` on a
## `[u8;N]` array must type `x` as `u8`, so a subsequent `x + <literal>` (BOTH operands non-index) is
## width-checked. 200 + 100 = 300 > 255 → the guard TRAPS (x86 → 132) instead of the native-width add
## silently returning 300 (exit 44). Companion checked_index_bind_ok confirms the in-range case (42).
## Cross-backend since #683: the emit twins type the unannotated binding through
## `lower_layout::local_narrow` (they answered 300 → exit 44 before).
main := fn() -> u64 {
  xs : [u8; 4] = [200, 100, 1, 2]
  i : u64 = 0
  x := xs[i]
  y := x + 100
  return u64(y)
}
