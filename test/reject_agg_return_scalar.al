## SOUNDNESS NET (R1, TYP-6 sibling): a fn declaring a builtin-SCALAR return type that
## `return`s a struct/enum VALUE used to silently miscompile — the scalar epilogue delivered only the
## aggregate's word 0 in %rax (`g()` returned rc=41, the value of field `a`, discarding `b`). The
## compiler must instead FAIL LOUD at build time. A non-zero build rc is the acceptable outcome; a valid
## binary with a wrong result is the forbidden silent miscompile. Registered with `build_reject`.
S := struct { a : u64, b : u64 }
g := fn() -> u64 {
  s := S(a = 41, b = 99)
  return s
}
main := fn() -> u64 { return g() }
