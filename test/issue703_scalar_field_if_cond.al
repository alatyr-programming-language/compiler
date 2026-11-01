## e2e — issue #703: the scalar-owner field access as an if condition operand.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main f00fcd8c, native x86_64): check 0, build 0, exit 7: the
## fabricated zero chose the branch.
main := fn() -> u64 {
  x : u64 = 3
  if x.a == 0 { return 7 }
  1
}
## expect: reject "a scalar has no field to name at line 6 in issue703_scalar_field_if_cond"
