## sema/§ limits (I5/I9, FND-10; the 1:1 allow-list is CG-12): a translation unit declaring
## `@limits(no_abstractions)` may use ONLY the 1:1 assembly surface — a library value-operator is a
## structured abstraction (its checked instantiation is guarded → not 1:1), so `return 40 + 2` (an
## `Expr::Bin`) violates the unit's contract → REJECT. Without the limit this is a valid program → 42.
@limits(no_abstractions)
main := fn() -> u64 {
  return 40 + 2
}
