## e2e — issue #703: a STORE through a field of a scalar owner.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main f00fcd8c, native x86_64): check 0, build 0, exit 3: the
## store landed nowhere and the value read back unchanged.
main := fn() -> u64 {
  mut x : u64 = 3
  x.a = 4
  x
}
## expect: reject "a scalar has no field to name at line 6 in issue703_scalar_field_store"
