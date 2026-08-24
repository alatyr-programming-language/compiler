## BYTES: a module-level fixed byte-array initializer must not call at runtime.
## The frozen lower emits no call before _start: the mutable global's byte storage is zero
## (and the const path has no materialized array value), so both reads silently lose 42.
## This lane must turn both paths into a located reject while preserving literal/scalar globals
## and function-local [u8;4] return/index behavior.
build := fn() -> [u8; 4] {
  mut t : [u8; 4] = [0; 4]
  t[2] = 42
  t
}

mut MG : [u8; 4] = build()
CG := build()

main := fn() -> u64 {
  u64(MG[2]) + u64(CG[2])
}
