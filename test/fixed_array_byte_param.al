## BYTES / fixed-array parameter ABI: a concrete `[u8; N]` parameter receives
## the packed byte pointer from a typed local, and a callee can re-pass it.
sum_bytes := fn(xs : [u8; 4]) -> u64 {
  if u64(bytes(xs)[0]) != 11 { return 0 }
  return u64(xs[0]) + u64(xs[1]) + u64(xs[2]) + u64(xs[3])
}

forward_bytes := fn(xs : [u8; 4]) -> u64 {
  return sum_bytes(xs)
}

sum_signed_bytes := fn(xs : [i8; 2]) -> i64 {
  return i64(xs[0]) + i64(xs[1])
}

sum_bit_bytes := fn(xs : [bits8; 2]) -> u64 {
  return u64(xs[0]) + u64(xs[1])
}

main := fn() -> u64 {
  mut xs : [u8; 4] = [11, 22, 33, 44]
  if forward_bytes(xs) != 110 { return 1 }
  mut signed : [i8; 2] = [-2, 3]
  if sum_signed_bytes(signed) != 1 { return 2 }
  mut bits : [bits8; 2] = [5, 6]
  if sum_bit_bytes(bits) != 11 { return 3 }
  42
}
