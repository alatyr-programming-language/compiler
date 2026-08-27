## Regression for #169: a valid standard-byte struct returned by value must preserve
## the second narrow field. The pre-fix cross-backend result is 70, not 75.

T := struct { a : u8, b : u8 }
mk := fn() -> T { T(a = 7, b = 5) }

main := fn() -> u64 {
  r := mk()
  u64(r.a) * 10 + u64(r.b)
}
