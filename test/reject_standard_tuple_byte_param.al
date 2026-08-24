## A direct byte-array tuple parameter remains outside the local-only standard-layout tier.
take := fn(t : ([u8; 4], u64)) -> u64 {
  t.0[1]
}

main := fn() -> u64 {
  t : ([u8; 4], u64) = ([1, 2, 3, 4], 9)
  take(t)
}
