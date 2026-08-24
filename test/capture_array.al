## e2e: a lambda CAPTURING a non-scalar local whose type comes from its `: T` ANNOTATION (an array
## `arr : [u64;3]`), not a directly-bound struct/enum literal. Formerly `d_capture_pass` fail-loud'd
## (d_local_type_span only read a directly-bound `d_lit_type_span` RHS); now it falls back to the local's
## `: T` annotation, so `arr` gets a TYPED by-ref capture param and `arr[0]` resolves in the lifted fn.
## The lambda escapes (passed to `apply`), so it must lift + inject the capture. arr[0]=10, +32 = 42.
apply := fn(f : fn(u64) -> u64, v : u64) -> u64 { return f(v) }
main := fn() -> u64 {
  arr : [u64; 3] = [10, 20, 12]
  g := fn(v : u64) -> u64 { return v + arr[0] }
  return apply(g, 32)
}
