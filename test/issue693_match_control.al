## e2e — issue #693 CONTROL 3: the LEGITIMATE way to reach an enum payload. `match` and its binding
## patterns are the access form the language gives an enum, and the refusal must leave it untouched.
## 33 = 11 + 22, the two payload words of the constructed variant.
E := enum { A, B(u64, u64) }
main := fn() -> u64 {
  v := E.B(11, 22)
  match v {
    E.A => { 1 }
    E.B(x, y) => { x + y }
  }
}
