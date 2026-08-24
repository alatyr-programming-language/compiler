## e2e — the CALL-ARGUMENT mirror. Declarations §3.4: an integer literal "takes its type from
## context — the annotation `T`, or the target place/PARAMETER", so `f(300)` for `f(v : u8)` is the
## same §9.1 compile error as `x : u8 = 300`. Behind every gate the argument-conformance rule already
## carries (unambiguous non-generic non-variadic callee, a real `in` parameter at this index).
## Located at the call (line 10).
f := fn(v : u8) -> i64 {
  return i64(v)
}

main := fn() -> i64 {
  return f(300)
}
