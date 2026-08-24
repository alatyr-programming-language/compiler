## e2e — a nested `if / else if / else` chain written as the LAST statement of an enclosing `else if`
## arm, inside a `while` body. The classifier that decides STATEMENT-if vs tail value-if peeked only
## the FIRST branch's body for a statement head; here the first branch body is a bare CALL (which is
## not one), every LATER branch is an assignment, and the chain is the last thing in its block — so it
## was taken for a tail value-if and the value parser then walked over the `=` signs and drifted the
## cursor OUT of the function. The observed failure was a diagnostic many lines PAST the construct.
## Every arm of both chains is exercised with a DISTINCT result, so taking the wrong branch cannot
## pass: pick(0..4, 9) must give 1, 2, 3, 4, 7, 5 in that order. Returns 42; a mismatch returns
## 60 + a bitmask naming which inputs disagreed (all values < 126, so wasm's proc_exit accepts them).
mut R := 0
setr := fn(x : u64) -> u64 { R = x ; return x }
pick := fn(n : u64) -> u64 {
  R = 0
  mut i := 0
  while i < 1 {
    i = i + 1
    if n == 0 {
      R = 1
    } else if n < 5 {
      if n == 1 {
        setr(2)
      } else if n == 2 {
        R = 3
      } else if n == 3 {
        R = 4
      } else {
        R = 7
      }
    } else {
      R = 5
    }
  }
  return R
}
main := fn() -> u64 {
  mut bad := 0
  if pick(0) != 1 { bad = bad + 1 }
  if pick(1) != 2 { bad = bad + 2 }
  if pick(2) != 3 { bad = bad + 4 }
  if pick(3) != 4 { bad = bad + 8 }
  if pick(4) != 7 { bad = bad + 16 }
  if pick(9) != 5 { bad = bad + 32 }
  if bad != 0 { return 60 + bad }
  return 42
}
