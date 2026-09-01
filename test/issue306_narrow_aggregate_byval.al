## AXIS coverage for #306: aggregate-byval width narrow x backend wasm/a64/rv64.
## Both byte fields are non-zero when the aggregate crosses the function boundary.
BytePair := struct { left : u8, right : u8 }

sum_pair := fn(p : BytePair) -> u64 {
  return u64(p.left) + u64(p.right)
}

main := fn() -> u64 {
  pair := BytePair(left = 40, right = 2)
  sum_pair(pair)
}
