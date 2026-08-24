## sema/§60 (CF-1): a VALUE match covering ALL variants must ACCEPT (must not over-reject). Returns 42.
Opt := enum { None, Some(u64) }
f := fn(o : Opt) -> u64 { return match o { None => { 0 }; Some(v) => { v } } }
main := fn() -> u64 { return f(Opt.Some(42)) }
