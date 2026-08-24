## REGALLOC-PATH checked-overflow trap (I11 / CG-8, regalloc commit 4). Unlike `checked_mul_ovf`
## (which returns via an explicit `return b` → the text emit path), this fn is a scalar-leaf
## TRAILING-VALUE checked `*` — exactly the shape `emit_fn_ir` register-allocates. It must STILL
## emit the overflow guard (`mulq %…; jnc CONT; ud2; CONT:`) and TRAP on overflow (x86 exact 132),
## proving the register-allocated path preserves checked arithmetic (a dropped guard = a silent
## miscompile). 6148914691236517206 * 3 = 2^64 + 2 overflows u64. unchecked would wrap to 2.
main := fn() -> u64 {
  a := 6148914691236517206
  a * 3
}
