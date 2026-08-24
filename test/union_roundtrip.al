## Raw union (spec Types §6.3) — ROUND TRIP: write a member, read the SAME member back → the value.
## `U.a(42)` stores 42 at offset 0 (no discriminant, untagged); `u.a` reads offset 0 as `a`'s type.
U := union { a(u64), b(u64) }
main := fn() -> u64 {
  u := U.a(42)
  return u.a
}
