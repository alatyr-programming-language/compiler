## fmt — the tryable `?` operator (`Expr::Try`) must round-trip through `alatyr fmt` (idempotent) and
## the reformatted source still build+run. `get()?` unwraps the success payload (variant 0); `run`
## returns the same enum, so a success flows through and `main` matches out 42. Construction uses the
## dot form (`Opt.Some(42)`); the match pattern uses the `::` form with expression-body arms (the
## shape `alatyr fmt` models).
Opt := enum { Some(u64), None }
get := fn() -> Opt { Opt.Some(42) }
run := fn() -> Opt {
  x := get()?
  Opt.Some(x)
}
main := fn() -> u64 {
  match run() {
    Opt::Some(v) => v
    Opt::None => 0
  }
}
