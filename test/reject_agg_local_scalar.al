## SOUNDNESS NET (R2, TYP-6 sibling / D69): a local annotated with a builtin-SCALAR type bound to a
## struct/enum VALUE (`x : u64 = s`) used to silently miscompile — the scalar store kept only the
## aggregate's word 0 (`x` became 41, the value of field `a`, discarding `b`). The compiler must instead
## FAIL LOUD at build time. A non-zero build rc is the acceptable outcome; a valid binary with a wrong
## result is the forbidden silent miscompile. Registered with `build_reject` in scripts/e2e.sh.
S := struct { a : u64, b : u64 }
main := fn() -> u64 {
  s := S(a = 41, b = 99)
  x : u64 = s
  return x
}
