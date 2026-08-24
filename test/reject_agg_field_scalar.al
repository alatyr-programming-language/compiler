## SOUNDNESS NET (P3, TYP-6 / D69): storing a struct/enum VALUE into a builtin-SCALAR struct FIELD
## (`t.x = s` with field `x : u64`, `s : S`) used to silently miscompile — the scalar store kept only
## the aggregate's word 0 (`t.x` became 41, the value of field `a`, discarding `b`). The compiler must
## instead FAIL LOUD at build time. A non-zero build rc is the acceptable outcome; a valid binary with
## a wrong result is the forbidden silent miscompile. Registered with `build_reject` in scripts/e2e.sh.
S := struct { a : u64, b : u64 }
T := struct { x : u64 }
main := fn() -> u64 {
  mut t := T(x = 0)
  s := S(a = 41, b = 99)
  t.x = s
  return t.x
}
