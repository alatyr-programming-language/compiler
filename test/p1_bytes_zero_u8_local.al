## P1-BYTES: a zero-length byte array local has length 0 and emits no element stores.
main := fn() -> u64 {
  xs : [u8; 0] = [0; 0]
  if xs.len == 0 { 42 } else { 1 }
}
