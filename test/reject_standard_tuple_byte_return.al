## A direct byte-array tuple return remains outside the local-only standard-layout tier.
make := fn() -> ([u8; 4], u64) {
  ([1, 2, 3, 4], 9)
}

main := fn() -> u64 {
  t := make()
  t.0[1]
}
