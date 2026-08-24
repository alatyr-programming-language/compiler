## FN-6 — an ELEMENT CALLEE whose chain has NO NAMED ROOT (`deref(pp)[0](10)`) must be rejected
## fail-loud, NOT silently miscompiled. The named-root spellings now WORK — `fs[0](10)`, `fs[i](x)`,
## `t.fs[0](x)` are locked by `fn_value_expr_callee` — because the representation borrows the callee
## NAME SPAN from the chain's root variable (the node still carries a name, not an expression) and
## recovers the element's fn TYPE from that root's declaration, which is what makes the call
## ARITY-checkable. A chain rooted in a LOAD (or in any other non-`Var` head) offers neither: there is
## no name to borrow and no declaration to read the signature off, so the call could only be lowered
## blind. Left unhandled the trailing `(10)` was silently DROPPED and the element's fn value — its CODE
## ADDRESS — leaked out as the result. Bind the element to a name first: `g := deref(pp)[0]` then
## `g(10)`, the working indirect-call path (locked by `fn_value_bound_callee`).
add1 := fn(x : u64) -> u64 { return x + 1 }
dbl := fn(x : u64) -> u64 { return x * 2 }
main := fn() -> u64 {
  fs : [fn(u64) -> u64; 2] = [add1, dbl]
  pp := ptr(fs)
  return deref(pp)[0](10)
}
