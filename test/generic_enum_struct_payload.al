## Regression: a generic enum-instance whose type-param monomorphizes to a MULTI-WORD STRUCT must
## deliver the WHOLE payload through construction + return + match-binding (register/staging path).
## `Option(V)` / `Result(_, V)` with V = a 2-word struct previously truncated word 1 (same-fn bind)
## or CRASHED the compiler (a by-ref struct-param payload underflowed a checked slot offset).
Rec := struct { a : i64, b : i64 }

## generic Option payload: construct `Option(V).Some(v)` from a by-ref struct param, return + match-bind.
gopt := fn(V : type, v : V) -> Option(V) { Option(V).Some(v) }
## generic Result payload: the Ok arm carries the struct.
gres := fn(V : type, v : V) -> Result(V, u64) { Result(V, u64).Ok(v) }

main := fn() -> u64 {
  ## (1) generic Option(struct) — read BOTH fields (12 + 8 = 20)
  q := Rec(a = 12, b = 8)
  r := gopt(Rec, q)
  s0 := match r { Option.Some(x) => { u64(x.a + x.b) }  Option.None => { u64(0) } }
  ## (2) generic Result(struct, _) — Ok payload struct, read BOTH fields (10 + 12 = 22)
  p := Rec(a = 10, b = 12)
  r2 := gres(Rec, p)
  s1 := match r2 { Result.Ok(y) => { u64(y.a + y.b) }  Result.Err(_) => { u64(0) } }
  ## (3) same-function local bind of a concrete Option(struct) — read BOTH fields (1 + 0 handled elsewhere)
  s0 + s1
}
