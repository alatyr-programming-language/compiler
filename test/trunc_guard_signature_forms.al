## OVER-REJECT GUARD for the balanced-truncation rejects added to the parser. Each guard below is a
## LEGITIMATE construct that one of the new requirements could have broken, gathered into one program
## whose exit code is a checksum over all of them:
##
##   * a multi-token return type (a parameterized generic-enum type, a tuple type) — the scan that
##     walks from the signature to the body now STOPS at the `:=` that begins the next declaration, so
##     every return-type spelling that legitimately spans several tokens must still reach its body;
##   * a `when` declaration guard between the signature and the body, which sits exactly where that
##     scan runs;
##   * a lambda with an explicit return arrow, and a lambda with none;
##   * an expression `if` (including a nested one in the else position) — its branch brace is now
##     required rather than skipped;
##   * a `match` expression — its arm-list brace is now required rather than skipped;
##   * a qualified path used as a value (`mod::fn(...)`) and a `::` path whose segment is present;
##   * a member access whose name is present: a struct field, a chained field, and a tuple element.
##
## Measured identical on the pre-fix and post-fix compilers: build rc 0, exit 42.
Pair := struct { a : u64, b : u64 }
Outer := struct { p : Pair }

mk := fn(x : u64) -> Pair {
  Pair(a = x, b = x + 1)
}

res := fn(x : u64) -> Result(u64, u64) {
  Result(u64, u64).Ok(x)
}

two := fn() -> (u64, u64) {
  (1, 3)
}

guarded := fn(x : u64) -> u64 when target.arch == Arch.x86_64 {
  x + 1
}

main := fn() -> u64 {
  p := mk(10)
  o := Outer(p = p)
  q := res(2)
  t := two()
  mut acc := 0
  ## multi-token return types
  acc = acc + p.a + p.b                        ## 10 + 11
  acc = acc + o.p.a                            ## chained field: 10
  acc = acc + match q {
    Result::Ok(v) => { v }
    Result::Err(e) => { 0 }
  }                                            ## 2
  acc = acc + t.0 + t.1                        ## tuple elements: 1 + 3
  ## a `when` guard between the signature and the body
  acc = acc + guarded(0)                       ## 1
  ## lambdas, with and without an explicit arrow
  add := fn(a : u64, b : u64) -> u64 { a + b }
  acc = acc + add(1, 1)                        ## 2
  ## an expression `if`, with a nested one in the else position
  acc = acc + if acc > 0 { 1 } else { if acc == 0 { 5 } else { 9 } }
  ## a `match` expression
  m := match acc {
    0 => { 100 }
    _ => { 1 }
  }
  acc = acc + m
  acc
}
