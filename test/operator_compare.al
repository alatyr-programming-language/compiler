## e2e — §2 operator overloading for a COMPARISON operator over a user type, in CONDITION position.
## `@inline <` over `Ver` compares the wrapped field. `x < y` (3 < 7 -> true) routes through it; the
## `if` then selects 42. Exercises the `<` (op 24) routing + a routed Bin used as a branch condition.
## A comparison operator-function yields `bool` (Stdlib §2.6, OP-2); this fixture declared `-> u64`
## until `check_expr`'s `Bin` arm first ran and refused the `bool` body returned as `u64` (#716).
Ver := struct { n : u64 }
@inline < := fn(a : Ver, b : Ver) -> bool {
  a.n < b.n
}
main := fn() -> u64 {
  x := Ver(n = 3)
  y := Ver(n = 7)
  if x < y { 42 } else { 0 }
}
