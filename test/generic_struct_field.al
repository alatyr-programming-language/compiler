## Generic-STRUCT-instance field access / construction (the struct parallel of the nested
## generic-ENUM fix, commit a118453). Three shapes, all resolving a generic-struct instance by
## its BASE name (stripping the `(…)` type-args) for the struct-decl LOOKUP while keeping the FULL
## span to recover the instance's type-args when sizing:
##   1. a generic 2-word STRUCT-instance LOCAL construct + field-read (`Slice(u8)(...).len`);
##   2. a 2-TYPE-PARAM generic struct (`Pair(u64, u64)`) — the shape the `omap` container needs;
##   3. a generic-struct instance used as a STRUCT FIELD (`Holder { s : Slice(u8), tag }`) — the
##      parenthesized `Slice(u8)` field type must size as 2 words so `tag` does not overlap it
##      (before the fix `Slice(u8)` missed `struct_decl_of`, sizing the field as 1 word → `h.s.len`
##      read the wrong slot). Returns 42.

Slice := fn(T : type) -> type { return struct { ptr : ptr(T), len : usize } }
Pair  := fn(A : type, B : type) -> type { return struct { a : A, b : B } }
Holder := struct { s : Slice(u8), tag : usize }

main := fn() -> u64 {
  ## (1) generic single-type-param struct LOCAL: read field 1 (`len`) at its correct offset.
  sl := Slice(u8)(ptr = "x".ptr, len = 5)
  a := u64(sl.len)                              ## 5

  ## (2) 2-type-param generic struct: both fields at the right offsets.
  q := Pair(u64, u64)(a = 3, b = 4)
  b := q.a + q.b                                ## 7

  ## (3) generic-struct instance as a STRUCT FIELD: the 2-word `Slice(u8)` field must not be
  ## clobbered by the following `tag` word.
  h := Holder(s = Slice(u8)(ptr = "y".ptr, len = 5), tag = 25)
  c := u64(h.s.len) + u64(h.tag)                ## 5 + 25 = 30

  return a + b + c                              ## 5 + 7 + 30 = 42
}
