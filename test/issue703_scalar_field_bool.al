## e2e — issue #703: a `bool` owner, compared in an if condition.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main f00fcd8c, native x86_64): check 0, build 0, exit 1.
main := fn() -> u64 {
  b : bool = true
  if b.q == true { return 1 }
  0
}
## expect: reject "a scalar has no field to name at line 5 in issue703_scalar_field_bool"
