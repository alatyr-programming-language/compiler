## BYTES carrier argument: a two-word fixed-array return can feed a fixed-array parameter.
build := fn() -> [u8; 16] {
  mut t : [u8; 16] = [0; 16]
  t[15] = 42
  t
}

read := fn(T : type, a : T) -> u64 {
  u64(a[15])
}

main := fn() -> u64 {
  read([u8; 16], build())
}
