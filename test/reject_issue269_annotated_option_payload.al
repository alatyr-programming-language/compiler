## Issue #269 / Types §4.1–§4.3 / Declarations §3.1 — an Option value remains distinct from its
## named-struct payload when a local annotation is used as the destination.
Payload := struct { value : u64 }
make_option := fn() -> Option(Payload) { return Option(Payload).Some(Payload(value = 7)) }
bad := fn() -> u64 {
  value : Payload = make_option()
  return value.value
}
main := fn() -> u64 { return 42 }
