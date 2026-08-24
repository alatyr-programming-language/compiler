## e2e (TUPLE return from a function — multiple return values). Tuples are word-arrays (`ArrayLit`)
## and worked as locals (`t := (a,b); t.0`), but a `-> (T0, T1, …)` return type was not recognized as
## an aggregate (`fn_returns_struct` keys on a named struct; a tuple has no backing Decl), so the fn
## returned only word 0 and the caller bound the result as a scalar. Now the parser captures the
## balanced `(…)` return span, `fn_returns_tuple`/`tuple_words` recognize + size it, the return-emit
## delivers each component via the register-return convention (word k → %rax/%rdx/%rcx/…, reusing
## `emit_struct_value`'s new ArrayLit arm), and the caller binds `t := f()` as an N-word tuple local
## and stages the return registers into it. Exercises a 2-tuple (early `return`), a 3-tuple (trailing
## value, no `return`), and computed components (divmod). (A GROUPED trailing expression over these
## bindings is exercised by `call_bind_paren` — it used to miscompile via `is_generic_inst`.)
divmod := fn(a : u64, b : u64) -> (u64, u64) { (a / b, a % b) }
pair := fn() -> (u64, u64) { return (40, 2) }
three := fn() -> (u64, u64, u64) { return (10, 20, 12) }
main := fn() -> u64 {
  p := pair()               ## (40, 2)
  t := three()              ## (10, 20, 12)
  q := divmod(43, 10)       ## (4, 3)
  ## p.0+p.1 = 42; t sums to 42; q.0+q.1 = 7 -> 42 + (42-42) + (7-7)
  p.0 + p.1 + t.0 + t.1 + t.2 - 42 + q.0 + q.1 - 7
}
