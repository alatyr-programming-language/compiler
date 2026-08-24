## no_opt is a valid limit (the lean lower does no optimization, so it is trivially satisfied) — accept.
@limits(no_opt)
main := fn() -> u64 { 42 }
