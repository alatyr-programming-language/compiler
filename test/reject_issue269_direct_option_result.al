## Issue #269 / Functions §3.1–§3.2 — direct Option/Result return values are not
## concrete scalar or named-struct arguments. This is a control for the direct-call
## half of the lane; the parent already rejects this shape through an older fence.
Payload := struct { value : u64 }

make_result_scalar := fn() -> Result(u64, u64) { return Result(u64, u64).Ok(7) }
make_option_scalar := fn() -> Option(u64) { return Option(u64).Some(8) }
make_result_payload := fn() -> Result(Payload, u64) { return Result(Payload, u64).Ok(Payload(value = 9)) }
make_option_payload := fn() -> Option(Payload) { return Option(Payload).Some(Payload(value = 10)) }
take_scalar := fn(x : u64) -> u64 { return x }
take_payload := fn(x : Payload) -> u64 { return x.value }

bad_result_scalar_direct := fn() -> u64 { return take_scalar(make_result_scalar()) }
bad_option_scalar_direct := fn() -> u64 { return take_scalar(make_option_scalar()) }
bad_result_payload_direct := fn() -> u64 { return take_payload(make_result_payload()) }
bad_option_payload_direct := fn() -> u64 { return take_payload(make_option_payload()) }

main := fn() -> u64 { return 42 }
