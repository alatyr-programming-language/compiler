## e2e (bool + negative-literal match patterns). `true`/`false` pattern idents fell into the
## enum-VARIANT arm branch → a `bool` match mis-dispatched (a value never matched → 0); a negative
## `-N` pattern reached `int_at` on the `-` token (→ 0) and consumed one token, so the `=>` skip ate
## the digit → parser desync → a compiler stack-overflow CRASH. Both arm parsers (expression + statement
## match) now treat `true`/`false` as integer patterns (1/0) and consume `-N` as a negated literal.
pick := fn(b : bool) -> u64 {
  return match b { true => 40, false => 2 }
}
sgn := fn(x : i64) -> u64 {
  ## negative-literal patterns in a statement match
  mut r : u64 = 9
  match x { -5 => { r = 0 } -1 => { r = 0 } _ => { r = 0 } }
  return r
}
main := fn() -> u64 {
  a := pick(true)                       ## 40
  b := pick(false)                      ## 2
  ## expression match with a negative literal pattern, bound to a local
  n : i64 = 0 - 5
  z := match n { -5 => 0, -9 => 1, _ => 9 }   ## 0
  s := sgn(0 - 1)                       ## 0
  a + b + z + s                         ## 40 + 2 + 0 + 0 = 42
}
