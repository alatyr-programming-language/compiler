## DEFER (§9.3): a single defer + a plain fall-through (normal) exit — the cleanup runs. `body` returns
## 3; its deferred `mark()` sets FLAG=7 on the way out. main returns FLAG + body's result = 7 + 3 = 10
## (if the defer had NOT run, FLAG would stay 0 and the exit code would be 3).
mut FLAG : u64 = 0
mark := fn() -> u64 { FLAG = 7 ; 0 }
body := fn() -> u64 {
  defer mark()
  3
}
main := fn() -> u64 {
  r := body()
  return FLAG + r
}
