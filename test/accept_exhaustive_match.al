## sema/§60 (CF-1): a statement `match` covering ALL variants of the enum must ACCEPT (exhaustiveness
## is fail-open + must not over-reject a complete match). Returns 42.
Opt := enum { None, Some(u64) }
f := fn(o : Opt) -> u64 {
  match o { None => { return 0 }; Some(v) => { return v } }
  return 1
}
main := fn() -> u64 { return f(Opt.Some(42)) }
