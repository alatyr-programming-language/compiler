## sema/§1 (Track A): an enum-typed LOCAL used where a scalar is required must REJECT. check_expr now
## resolves a user enum/struct local to its concrete tag (via a pre-match accessor bypassing the
## scar-#2 big-match mis-dispatch), so `x : u64 = o` for an enum param `o` is a type mismatch.
Opt := enum { None, Some(u64) }
f := fn(o : Opt) -> u64 { x : u64 = o
  return x }
main := fn() -> u64 { return f(Opt.None) }
