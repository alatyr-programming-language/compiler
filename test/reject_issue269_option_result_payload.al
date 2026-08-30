## Issue #269 / Types §4.2–§4.4, §6.2 / Functions §2.3 — a tagged Option/Result
## value is not its payload. Each local binding below is intentionally ill-typed: the
## parent lost the concrete wrapper identity and lowered the first wrapper word as a scalar.
Payload := struct { value : u64 }

make_result_scalar := fn() -> Result(u64, u64) {
  return Result(u64, u64).Ok(7)
}
make_option_scalar := fn() -> Option(u64) {
  return Option(u64).Some(8)
}
make_result_payload := fn() -> Result(Payload, u64) {
  return Result(Payload, u64).Ok(Payload(value = 9))
}
make_option_payload := fn() -> Option(Payload) {
  return Option(Payload).Some(Payload(value = 10))
}
take_scalar := fn(x : u64) -> u64 { return x }
take_payload := fn(x : Payload) -> u64 { return x.value }

bad_result_scalar_local := fn() -> u64 {
  r := make_result_scalar()
  return take_scalar(r)
}
bad_option_scalar_local := fn() -> u64 {
  o := make_option_scalar()
  return take_scalar(o)
}
bad_result_payload_local := fn() -> u64 {
  r := make_result_payload()
  return take_payload(r)
}
bad_option_payload_local := fn() -> u64 {
  o := make_option_payload()
  return take_payload(o)
}

main := fn() -> u64 {
  return 42
}
