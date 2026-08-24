## Located boundary for P1-REQUIRE-AGG: raw unions share the enum-shaped declaration node but have no
## discriminant. Their @require path is intentionally deferred until the union overlap ABI is explicit.
U := union { a(u64), b(u64) }
valid := fn(u : U) -> bool { return true }
Checked := @require(valid) U

main := fn() -> u64 {
  x := Checked(U.a(42))
  return 1
}
