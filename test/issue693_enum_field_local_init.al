## e2e — issue #693, position 2 of 7: the same access as a local BINDING initializer.
##
## Parent verdict: check 0, build 0, exit 0 — the binding took the fabricated word and returned it.
E := enum { A, B(u64, u64) }
main := fn() -> u64 {
  v := E.B(11, 22)
  w := v.a
  w
}
