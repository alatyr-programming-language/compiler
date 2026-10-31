## e2e — issue #703: the owner is a PARAMETER declared `i64`.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main f00fcd8c, native x86_64): check 0, build 0, exit 0.
f := fn(p : i64) -> i64 { p.zz }
main := fn() -> i64 { f(4) }
## expect: reject "a scalar has no field to name at line 3 in issue703_scalar_field_param"
