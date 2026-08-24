## e2e — REGALLOC I11: a CHECKED division BY ZERO on the register-allocated scalar-leaf IR path MUST trap
## (not compute a bogus value). `dz` is scalar-leaf (only `/`) → the IR path emits a plain `divq`; dividing
## by zero raises the hardware #DE → SIGFPE → the process exits 136 (128 + 8), an I11 trap (exit ≥ 128) —
## the same trap the reference text path delivers. Locks in that widening `is_scalar_leaf_shape` to admit
## CHECKED division did NOT drop the div-by-zero trap.
dz := fn(a : u64, b : u64) -> u64 { a / b }
main := fn() -> u64 {
  dz(84, 0)
}
