## e2e — issue #693, position 7 of 7: the WRITE, which is a different path from every read above.
##
## The parser records `v.a = 5` as two NAME spans, not as an expression, so no expression walker ever
## sees this place and the read-side refusal cannot reach it. Parent verdict: check 0, build 0, exit
## **42** — the store was accepted and then dropped on the floor, with nothing said on any surface.
## 42 rather than 5 is what proves it was dropped rather than performed somewhere harmless.
E := enum { A, B(u64, u64) }
main := fn() -> u64 {
  mut v := E.B(11, 22)
  v.a = 5
  42
}
