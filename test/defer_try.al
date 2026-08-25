## DEFER + TRY (§9.3): the first body(0) call takes the None early-return path and its defer increments
## FLAG to 1. The second body(2) call takes the Some path, proves the payload is 2 by assigning FLAG=2,
## then its defer increments FLAG to 3. The final value therefore proves both WAT try branches and the
## cleanup on each exit.
mut FLAG : u64 = 0
mark := fn() -> u64 { FLAG = FLAG + 1 ; 0 }
half := fn(x : u64) -> Option(u64) { if x > 0 { return Option.Some(x) } return Option.None }
body := fn(x : u64) -> Option(u64) {
  defer mark()
  v := half(x)?
  if v == 2 { FLAG = 2 }
  return Option.Some(v + 1)
}
main := fn() -> u64 {
  r := body(0)
  body(2)
  return FLAG
}
