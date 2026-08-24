## FAIL-LOUD (correct-or-trap, I11): `xs[i].arr[j]` where the array-field element is a MULTI-WORD
## struct is NOT yet composed — the lower must PANIC (never emit a word-0-only silent-wrong read),
## so `build_reject` expects a non-zero build rc. Proves the deep-index resolvers don't over-accept.
P := struct { a : u64, b : u64 }
S := struct { pad : u64, arr : [P; 2] }
main := fn() -> u64 {
  mut xs : [S; 2]
  xs[0] = S(pad = 9, arr = [P(a = 10, b = 1), P(a = 20, b = 2)])
  u64(xs[0].arr[1])
}
