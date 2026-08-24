## sema/§1 (Track A): an enum-typed local used AS its own enum type must ACCEPT — the new resolution
## must not over-reject legitimate use (returned as the same enum; matched).
Opt := enum { None, Some(u64) }
id := fn(o : Opt) -> Opt { return o }
main := fn() -> u64 { m := id(Opt.Some(42))
  return match m { None => { 0 }; Some(v) => { v } } }
