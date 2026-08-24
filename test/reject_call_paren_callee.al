## FN-6 — a call through a PARENTHESIZED callee with a WRONG ARITY (`(add1)(41, 99, 7)`: three
## arguments to a one-parameter function) must be rejected, NOT silently miscompiled. A call carries a
## callee NAME SPAN, not an expression, so the whole argument list used to be silently DROPPED and
## `add1`'s CODE ADDRESS leaked out as the result — wrong arity and all, without a word.
## The parenthesized bare-name spelling is now SUPPORTED and parses as the plain call it is —
## `(add1)(41)` IS `add1(41)`, locked by `fn_value_expr_callee` — which is precisely what puts this
## program back under the ORDINARY arity diagnostic that rejects it here. A parenthesized ELEMENT
## (`(fs[0])(9)`) is supported too; every other parenthesized callee keeps its own located reject
## (`reject_iife` for a lambda).
add1 := fn(x : u64) -> u64 { return x + 1 }
main := fn() -> u64 {
  return (add1)(41, 99, 7)
}
