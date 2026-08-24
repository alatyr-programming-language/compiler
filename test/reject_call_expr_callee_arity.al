## FN-6 — a call through an EXPRESSION CALLEE must be ARITY-CHECKED. The callee is an element read, so
## no `fn` DECL backs it and the front end's ordinary arity diagnostic has nothing to compare against —
## which is exactly how `(add1)(41, 99, 7)` used to be accepted without a word (three arguments to a
## one-parameter function, the trailing list silently dropped). The lower recovers the element's fn TYPE
## from the array's declaration (`fs : [fn(u64) -> u64; 2]`) and compares the parameter count against
## the call: two arguments to a one-parameter fn value is a BUILD reject, never a wrong call.
## (`build_reject`, not `check_reject` — sema resolves no signature for the borrowed callee name.)
## The sound spellings are locked by `fn_value_expr_callee`.
add1 := fn(x : u64) -> u64 { return x + 1 }
dbl := fn(x : u64) -> u64 { return x * 2 }
main := fn() -> u64 {
  fs : [fn(u64) -> u64; 2] = [add1, dbl]
  return fs[0](10, 99)
}
