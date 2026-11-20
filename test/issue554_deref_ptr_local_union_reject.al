## Issue #554 / Types §6.3: a raw union's member is the bytes at offset 0, read as the member's type.
## `deref(ptr(x)).b` with `x := U.w(511)` is due 255 (`u8`). Without the union refusal, the
## `deref(ptr(local))` arm loaded the whole word and answered 511: a clean compile with a wrong value.
## The arm has no sized member read, so it must refuse with a located diagnostic.
##
## The twins trap at their field-access stub (#1187), listed in scripts/known-deviations.tsv.
U := union { b(u8), w(u64) }

main := fn() -> u64 {
  x := U.w(511)
  return u64(unchecked (deref(ptr(x)).b))
}
## expect: reject "raw union member read through deref(ptr(local))"
