## sema/§1 (Track A): returning an enum-typed local where the declared return type is a scalar must
## REJECT (the return-path type check now sees the resolved enum tag).
Opt := enum { None, Some(u64) }
f := fn(o : Opt) -> u64 { return o }
main := fn() -> u64 { return f(Opt.None) }
