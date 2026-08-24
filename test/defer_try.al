## DEFER (§9.3): a defer runs on the `?` (try) early-return path. `body` registers mark() (sets FLAG=1),
## then `half(x)?` — for x==0, half returns None, so `?` early-returns None from body, running the defer
## on the way out. main returns FLAG = 1 (proving the defer ran on the `?`-propagation exit).
mut FLAG : u64 = 0
mark := fn() -> u64 { FLAG = 1 ; 0 }
half := fn(x : u64) -> Option(u64) { if x > 0 { return Option.Some(x) } return Option.None }
body := fn(x : u64) -> Option(u64) {
  defer mark()
  v := half(x)?
  return Option.Some(v + 1)
}
main := fn() -> u64 {
  r := body(0)
  return FLAG
}
