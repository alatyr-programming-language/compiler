## e2e (a 1-FIELD struct returned by value). `fn_returns_struct` required a >= 2-word struct, so a
## single-field struct return (`fn() -> P` where `P := struct { x : u64 }`) fell to the SCALAR return
## path: the caller bound the result as a scalar and `p.x` read 0. A 1-word struct rides %rax (SysV
## integer class) like a scalar but must be BOUND as a struct so `.field` resolves — `fn_returns_struct`
## now accepts 1..7 words. Exercises a direct 1-field return + a wrapping/unwrapping round-trip.
One := struct { x : u64 }
mk := fn(v : u64) -> One { return One(x = v) }
unwrap := fn(o : One) -> u64 { return o.x }
main := fn() -> u64 {
  a := mk(40)               ## One{40}
  b := mk(2)                ## One{2}
  a.x + b.x + unwrap(mk(0)) ## 40 + 2 + 0 = 42
}
