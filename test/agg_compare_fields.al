## e2e — the CORRECT structural comparison for a MULTI-WORD struct: a `comptime for`-over-fields
## per-field compare (the shape `derive::eq` uses). Each `a.(f) != b.(f)` compares a SCALAR field, so
## every word is checked — unlike a bare `a == b`, which the lower now rejects (see reject_agg_compare)
## because it would compare word 0 only. This locks the sound path: a 2-word struct differing ONLY in
## word 1 (`y`) is correctly reported not-equal, and an equal pair equal. 1 + 41 = 42.
P := struct { x : u64, y : u64 }
speq := fn(T : type, a : T, b : T) -> bool {
  comptime for f in typeinfo(T).fields {
    if a.(f) != b.(f) { return false }
  }
  return true
}
main := fn() -> u64 {
  a := P(x = 5, y = 7)
  b := P(x = 5, y = 9)   ## differ in word 1 only
  c := P(x = 5, y = 7)   ## equal to a
  mut r : u64 = 0
  if speq(P, a, b) == false { r = r + 1 }   ## word-1 difference detected → not equal
  if speq(P, a, c) { r = r + 41 }           ## all fields equal → equal
  r
}
