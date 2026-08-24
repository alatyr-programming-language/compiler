## e2e — Types §9.1: "An integer literal is a compile-time number; its type is inferred from context,
## and its representability in that type is CHECKED AT COMPILE TIME — a literal outside the target
## type's range is a compile error (I11), never a silent wrap."
##
## `x : u8 = 300` was accepted in silence and the program ran on a truncated 44. `resolve_ty`
## collapses every integer WIDTH onto one tag, so the bound cannot come from the tag; sema reads it
## from the annotation's type NAME instead. Located at the binding (line 9).
main := fn() -> i64 {
  x : u8 = 300
  return i64(x)
}
