## e2e (build_reject) — `for x in <ENUM-element ARRAY GLOBAL>` must FAIL LOUD. The global-array `for`
## path binds the loop var as a single WORD and reads `LABEL + i*8` per iteration; with a `1 + max-
## payload`-word element that is mid-element — a silent wrong-discriminant read. Index it instead
## (`for i in 0..N { match GE[i] { … } }`), which is the strided path.
E := enum { N, A(u64) }
mut GE := [E.A(5), E.N]
main := fn() -> u64 {
  mut s : u64 = 0
  for e in GE { match e { E::N => {} E::A(n) => { s = s + n } } }
  s
}
