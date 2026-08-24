## e2e (2-field struct-valued if-EXPRESSION with call branches). Reads .v + .w.
Q := struct { v : u64, w : u64 }
f := fn() -> Q { return Q(v = 40, w = 2) }
g := fn() -> Q { return Q(v = 1, w = 1) }
main := fn() -> u64 {
  c := u64(1)
  x := if c > 0 { f() } else { g() }
  return x.v + x.w
}
