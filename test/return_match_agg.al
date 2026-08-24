## e2e (an AGGREGATE — struct or tuple — returned via a `match` expression). `emit_struct_value` has
## no `Match` arm, so `return match n { … => P(…) }` / a trailing `match n { … => (a,b) }` delivered
## {0} (a silent miscompile). A `Stmt::Return` whose value is a `match` and whose fn returns a
## struct/tuple now routes through `emit_return_value` (dispatch the scrutinee, deliver each arm's
## aggregate via the register-return convention). Restricted to the aggregate case — enum/scalar/str
## `return match` keep their existing paths (emit_gas has a Match arm). Exercises a struct via
## `return match`, a tuple via `return match`, and a tuple via a TRAILING match (no `return`).
Pair := struct { a : u64, b : u64 }
pick_s := fn(n : u64) -> Pair { return match n { 0 => Pair(a = 1, b = 1), _ => Pair(a = 30, b = 2) } }
pick_t := fn(n : u64) -> (u64, u64) { return match n { 0 => (1, 1), _ => (6, 2) } }
pick_tr := fn(n : u64) -> (u64, u64) { match n { 0 => (0, 0), _ => (1, 1) } }
name := fn(n : u64) -> str { return match n { 0 => "zero", _ => "other" } }   ## str via return-match
Opt := enum { Some(u64), None }
wrap := fn(n : u64) -> Opt { return match n { 0 => Opt.None, _ => Opt.Some(4) } }   ## enum via return-match
main := fn() -> u64 {
  s := pick_s(5)            ## Pair(30, 2)
  t := pick_t(5)            ## (6, 2)
  r := pick_tr(5)           ## (1, 1)
  nm := name(5)             ## "other" (len 5)
  e := wrap(5)              ## Opt.Some(4)
  ev := match e { Opt::Some(x) => x, Opt::None => 0 }   ## 4
  s.a + s.b + t.0 + t.1 + r.0 + r.1 + nm.len - 5 + ev - 4   ## 32 + 8 + 2 + 5 - 5 + 4 - 4 = 42
}
