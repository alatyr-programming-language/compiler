## FN-6 — an IMMEDIATELY-INVOKED function value `(fn(...){...})(args)` (IIFE) must be rejected
## fail-loud, NOT silently miscompiled. `Expr::Call`'s callee is a NAME span, so a call applied to a
## parenthesized lambda cannot be represented; before the guard the trailing `(40)` was dropped and the
## lambda's code pointer leaked out as the value (the process exit was the low byte of its address — a
## silent miscompile, violating the "0 silent miscompiles" invariant). Bind the lambda to a name first.
main := fn() -> u64 {
  return (fn(n : u64) -> u64 { return n + 2 })(40)
}
