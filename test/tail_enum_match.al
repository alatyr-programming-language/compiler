## e2e — two fixes exercised together:
##  1. a TAIL value-`match` over an ENUM scrutinee in an enum-returning fn (`conv`'s body is
##     `match b { Full(v) => Opt.Some(v) ; Empty => Opt.None }` as the trailing return expr, bare arms
##     → an Expr::Match). Previously fell through to `emit_enum_value(Match)` → `{0,0}` (silent
##     miscompile); `emit_return_value` now dispatches + binds + delivers each arm via the return
##     convention.
##  2. a NULLARY enum-literal binding/arg (`b2 := Box.Empty`, `conv(b2)`): the parser now emits an
##     `EnumLit` (np 0) for a bare `E.V` whose base names a known enum, so the binding sizes as the
##     full enum and by-ref passing works (a plain `Field` sized it as a 1-word scalar → NULL deref).
## Returns 42.
Box := enum { Empty, Full(u64) }
Opt := enum { None, Some(u64) }

conv := fn(b : Box) -> Opt {
  match b {
    Full(v) => Opt.Some(v)
    Empty => Opt.None
  }
}

main := fn() -> u64 {
  b1 := Box.Full(42)
  a := conv(b1)
  mut r : u64 = 0
  match a { Opt::Some(x) => { r = x } Opt::None => { r = 7 } }
  b2 := Box.Empty
  e := conv(b2)
  match e { Opt::Some(x) => { r = r + 100 } Opt::None => { r = r + 0 } }
  return r
}
