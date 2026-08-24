## A direct byte-array tuple global remains outside the local-only standard-layout tier.
mut G : ([u8; 4], u64) = ([1, 2, 3, 4], 9)

main := fn() -> u64 {
  G.0[1]
}
