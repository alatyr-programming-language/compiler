## e2e — issue #703 residual: the owner is a local declared `u16`, a type the sema local table records no span for.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main e77d025e, native x86_64): check 0, build 0, exit 0, the
## fabricated zero read.
main := fn() -> u64 {
  x : u16 = 3
  u64(x.a)
}
## expect: reject "a scalar has no field to name at line 6 in issue703_scalar_field_subword_local"
