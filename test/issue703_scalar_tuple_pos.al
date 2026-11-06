## e2e — issue #703 residual: a TUPLE POSITION `.0` on a `u64` local; Types §6.1 gives `.N` to tuples only.
## a field access on a plain scalar owner names nothing (Modules §2: `.` reaches a field, a tuple position or a method; Types §6.1). Measured on the parent (main e77d025e, native x86_64): check 0, while build stopped in
## the lower with a non-located internal message: the two surfaces disagreed.
main := fn() -> u64 {
  x : u64 = 3
  x.0
}
## expect: reject "a scalar has no field to name at line 6 in issue703_scalar_tuple_pos"
