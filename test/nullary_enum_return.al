## Nullary (zero-parameter) enum-returning functions: the returned enum must be
## delivered correctly to the caller's `match`. Regression lock for a generic-
## resolution crash: a nullary call whose name COLLIDES with a loaded library
## generic (`get` vs `base/alloc`'s generic `get(T, a, h)`) mis-resolved to that
## generic in `generic_decl_of`'s arity-blind fallback, then
## `arg_expr_at(<empty args>, tparam_idx)` yielded a NULL Expr that
## `tuple_typearg_span` dereferenced -> a compiler SEGFAULT. The fn is named `get`
## on purpose so the collision path is exercised.
##
## Payload variants are single-word here: a multi-word enum-return payload
## (`B(u64, u64)`) drops its second word — a SEPARATE, pre-existing limitation that
## also affects with-param callees — kept out so this test isolates the nullary fix.

E := enum { A(u64), B(u64) }

## nullary, Option-returning, name collides with the generic `get`
get := fn() -> Option(u64) { return Option.Some(40) }

## nullary, user-enum-returning
mk_e := fn() -> E { return E.B(1) }

## nullary, Result-returning
mk_r := fn() -> Result(u64, u64) { return Result.Ok(1) }

main := fn() -> u64 {
  mut a := 0
  match get() { Option::Some(v) => { a = v } Option::None => { a = 100 } }
  match mk_e() { E::A(x) => { a = a + 100 } E::B(y) => { a = a + y } }
  match mk_r() { Result::Ok(z) => { a = a + z } Result::Err(e) => { a = a + 100 } }
  return a
}
