## e2e CONTROL for the statement-vs-value `if` classifier: a chain whose branches are ASSIGNMENTS,
## written as the last thing in the body of a function that promises a `u64`. Once the chain is
## recognised as a statement (which is what it is), the body supplies no result — so the program is
## ill-formed and must be REFUSED, at the function, not accepted with an invented return value. On the
## base compiler this same file failed for the wrong reason: a parse desync inside the chain.
setv := fn(x : u64) -> u64 { return x }
needs_a_value := fn(n : u64) -> u64 {
  mut r := 0
  if n == 0 {
    setv(n)
  } else if n == 1 {
    r = 5
  } else {
    r = 6
  }
}
main := fn() -> u64 { return needs_a_value(1) }
