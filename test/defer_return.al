## DEFER (§9.3): a defer runs before an early `return`. `body` registers mark() (sets FLAG=1), then early-
## returns 7 on the taken branch. main returns FLAG + body's result = 1 + 7 = 8 (proving the defer ran on
## the early-return path; without it the exit code would be 7).
mut FLAG : u64 = 0
mark := fn() -> u64 { FLAG = 1 ; 0 }
body := fn(x : u64) -> u64 {
  defer mark()
  if x > 0 { return 7 }
  return 0
}
main := fn() -> u64 {
  r := body(1)
  return FLAG + r
}
