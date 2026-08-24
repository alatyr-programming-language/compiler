## FN-6 CAPTURE of an ENUM via a `match` body — the lambda captures `e` (bound by an `E.A(..)` literal);
## the lift resolves its type E, gives it a typed by-ref param, and the `match e` in the lifted fn works.
## Match-arm payload binds (`x`) are arm-scoped locals, not captures. `E.A(42)` → 42.
E := enum { A(u64), B }
main := fn() -> u64 {
  e := E.A(42)
  f := fn(n : u64) -> u64 { match e { E::A(x) => { return x + n } E::B => { return n } } }
  return f(0)
}
