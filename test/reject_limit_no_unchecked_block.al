## sema/§ limits (I5/I9, FND-10): the SCOPED STATEMENT form `unchecked { … }` (D70/D82) is an
## `unchecked` escape exactly like the `unchecked <expr>` operator, so a unit declaring
## `@limits(no_unchecked)` must REJECT it.
##
## It did not. `reject_limit_no_unchecked.al` (the expression form) was rejected while this file — the
## SAME opt-out, respelled as a block — was ACCEPTED and built, so the unit contract was escapable by
## respelling. The deep scan's `Stmt::Unchecked` arm only RECURSED into the block's body instead of
## flagging the block itself. Without the limit this is a valid program → 42.
@limits(no_unchecked)
f := fn(a : u64, b : u64) -> u64 {
  mut r : u64 = 0
  unchecked { r = a + b }
  return r
}
main := fn() -> u64 { return f(40, 2) }
