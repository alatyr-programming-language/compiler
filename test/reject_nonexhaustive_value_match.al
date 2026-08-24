## sema/§60 (CF-1): a VALUE match (return/bind position) on a known enum missing a variant (no
## wildcard) must REJECT — the dual of reject_nonexhaustive_match for a value-position match, checked
## via check_expr's pre-match handler (the big-match Expr::Match arm is not dispatched under the seed).
Opt := enum { None, Some(u64) }
f := fn(o : Opt) -> u64 { return match o { None => { 0 } } }
main := fn() -> u64 { return f(Opt.None) }
