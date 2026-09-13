## e2e — issue #693, position 5 of 7: the same access in `return` position.
##
## Parent verdict: check 0, build 0, exit 0.
E := enum { A, B(u64, u64) }
main := fn() -> u64 {
  v := E.B(11, 22)
  return v.a
}
