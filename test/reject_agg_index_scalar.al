## SOUNDNESS NET (P2, TYP-6): storing a struct/enum VALUE into a SCALAR-element array element
## (`xs[0] = s` with `xs : [u64]`, `s : S`) used to silently miscompile — the single-word indexed
## store kept only the aggregate's word 0 (`xs[0]` became 41, the value of field `a`, discarding `b`).
## The compiler must instead FAIL LOUD at build time. A non-zero build rc is the acceptable outcome; a
## valid binary with a wrong result is the forbidden silent miscompile. Registered via `build_reject`.
S := struct { a : u64, b : u64 }
main := fn() -> u64 {
  xs := [0; 4]
  s := S(a = 41, b = 99)
  xs[0] = s
  return xs[0]
}
