## e2e — the SILENTLY WRONG half of the statement-vs-value `if` classifier defect (I11), in its
## portable shape: a chain written `else { if … else … }` — an else BLOCK holding the nested chain —
## as the last statement of a `while` body. The classifier peeked only the FIRST branch's body for a
## statement head; here that body is a bare CALL, so nothing was found, and a chain that is the last
## thing in its block was then taken for a tail value expression. The value parser read the nested
## branches as values and DROPPED both of their assignments: this file compiled clean on the base
## compiler and returned the wrong number for two of its three inputs. Each arm gets a distinct
## result so a branch taken in error cannot pass. Returns 42; a mismatch returns 60 + a bitmask of the
## disagreeing inputs (under 126, wasm's `proc_exit` ceiling).
mut R := 0
setr := fn(x : u64) -> u64 { R = x ; return x }
nested_else := fn(n : u64) -> u64 {
  R = 0
  mut i := 0
  while i < 1 {
    i = i + 1
    if n == 9 {
      setr(9)
    } else {
      if n == 0 {
        R = 5
      } else {
        R = 6
      }
    }
  }
  return R
}
main := fn() -> u64 {
  mut bad := 0
  if nested_else(9) != 9 { bad = bad + 1 }
  if nested_else(0) != 5 { bad = bad + 2 }
  if nested_else(1) != 6 { bad = bad + 4 }
  if bad != 0 { return 60 + bad }
  return 42
}
