## e2e (lean-lower: UFCS method call on a COMPLEX-expression receiver). `mk().sum()` — the receiver
## `mk()` is itself a CALL (returning a struct), not a simple variable. Two parser fixes cooperate:
## (1) `is_generic_enum_ctor` no longer treats `mk()` (EMPTY parens) as a zero-arg generic-enum-type
## application (a generic type needs ≥1 type arg), so `mk()` parses as an ordinary Call; (2) p_field
## desugars `<complex-receiver>.name(args)` to `Call(name, [receiver-expr, args…])`, keeping the
## receiver EXPRESSION (the EnumLit form kept only a name span, which a call receiver lacks). The
## receiver call's struct result then rides `emit_arg`'s aggregate-call-by-ref path. `40 + 2` = 42.
Pair := struct { a : u64, b : u64 }
mk := fn() -> Pair { Pair(a = 40, b = 2) }
sum := fn(p : Pair) -> u64 { p.a + p.b }
main := fn() -> u64 {
  mk().sum()
}
