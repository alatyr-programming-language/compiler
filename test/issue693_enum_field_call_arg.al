## e2e — issue #693, position 3 of 7: the same access as a CALL ARGUMENT.
##
## Parent verdict: check 0, build 0, exit 0 — `id` was handed the fabricated word.
E := enum { A, B(u64, u64) }
id := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  v := E.B(11, 22)
  id(v.a)
}
