## Issue #215 failure-first reproducer: a local [[u8; 2]; 2] must preserve
## contiguous inner-array stride through initialization, nested reads, and a
## nested write/read-back. The parent should return 42 but currently accepts
## this source and returns a wrong value or reaches a backend trap.
main := fn() -> u64 {
  mut xs : [
    [u8; 2] ## lexer trivia must not change the rejected semantic shape
    ; 2
  ] = [[1, 2], [3, 4]]
  if u64(xs[0][0]) != 1 { return 1 }
  if u64(xs[0][1]) != 2 { return 2 }
  if u64(xs[1][0]) != 3 { return 3 }
  if u64(xs[1][1]) != 4 { return 4 }
  xs[1][0] = 9
  if u64(xs[0][0]) != 1 { return 1 }
  if u64(xs[0][1]) != 2 { return 2 }
  if u64(xs[1][0]) != 9 { return 3 }
  if u64(xs[1][1]) != 4 { return 4 }
  42
}
