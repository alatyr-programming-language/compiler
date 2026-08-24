## P1-BYTES consumer seam: a bounded [u8; N] return carrier can feed a
## fixed-byte-array parameter directly. The callee must read the packed carrier
## through its existing by-reference parameter ABI, not treat %rax as an address.
build := fn() -> [u8; 4] {
  mut t : [u8; 4] = [0; 4]
  t[2] = 42
  t
}

take := fn(T : type, xs : T) -> u64 {
  u64(xs[2])
}

main := fn() -> u64 {
  take([u8; 4], build())
}
