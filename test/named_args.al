## FN ergonomics: NAMED CALL ARGUMENTS with REORDERING — `f(name = v, …)` binds each value to the
## parameter of that name regardless of source order (not positional). `combine(c=3, a=50, b=5)`
## reorders to a=50, b=5, c=3 → 50 - 5 - 3 = 42 (positional would be 3 - 50 - 5 = underflow). NB the
## callee must not shadow a builtin name (`sub`/`len`/`str_at`/…), which the toy grammar reserves.
combine := fn(a : u64, b : u64, c : u64) -> u64 { a - b - c }
main := fn() -> u64 {
  combine(c = 3, a = 50, b = 5)
}
