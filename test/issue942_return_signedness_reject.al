## e2e — #942, Types §4.2/§4.3: `a := 0` has no context, so it is the native signed `i64` (Types §9.1)
## and `b := a - 1` is an `i64` holding -1. Returning it from `-> u64` is a NUMERIC conversion, which is
## always explicit: the program is ill-formed and refused at the returned value, on every backend.
## Before the refusal x86_64 answered 255, the low byte of 2^64 - 1.
pick := fn(c : bool) -> u64 {
  a := 0
  b := a - 1
  if c { return b }
  7
}
main := fn() -> u64 {
  pick(true)
}
