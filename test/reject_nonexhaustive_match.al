## sema/§60 (CF-1): a statement `match` on a known enum whose arms are all plain variant patterns
## (no `_` wildcard) MUST cover every variant — omitting `Some` is a non-exhaustive match → REJECT.
## check resolves the scrutinee's enum type via local_ty directly (the by-value Ty return preserves the
## type-name span, unlike check_expr's Result-truncated payload).
Opt := enum { None, Some(u64) }
f := fn(o : Opt) -> u64 {
  match o { None => { return 0 } }
  return 1
}
main := fn() -> u64 { return f(Opt.None) }
