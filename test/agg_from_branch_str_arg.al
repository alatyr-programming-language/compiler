## e2e (a `str` produced by an `if` EXPRESSION delivered DIRECTLY as a call ARGUMENT). The str variant
## of `agg_from_branch_arg`: `f(if c { "hello!" } else { "yo" })` materializes the {ptr,len} of the
## chosen branch into the agg-temp (ek 4) and passes the block address by-ref. Was: the scalar default
## passed the data pointer as the by-ref pointer → a garbage `s.len()` (silent miscompile). len("hello!")
## == 6, so `36 + 6` -> 42.
f := fn(s : str) -> u64 { u64(s.len()) }
main := fn() -> u64 {
  c := true
  return 36 + f(if c { "hello!" } else { "yo" })
}
