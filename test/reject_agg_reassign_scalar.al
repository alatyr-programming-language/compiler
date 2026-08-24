## SOUNDNESS NET (P1, TYP-6): a plain RE-ASSIGN of a struct/enum VALUE into an existing SCALAR
## place (`G = s` with `mut G : u64`, `s : S`) used to silently miscompile — the scalar store kept only
## the aggregate's word 0 (`G` became 41, the value of field `a`, discarding `b`). The compiler must
## instead FAIL LOUD at build time. A non-zero build rc is the acceptable outcome; a valid binary with
## a wrong result is the forbidden silent miscompile. Registered with `build_reject` in scripts/e2e.sh.
S := struct { a : u64, b : u64 }
mut G : u64 = 0
main := fn() -> u64 {
  s := S(a = 41, b = 99)
  G = s
  return G
}
