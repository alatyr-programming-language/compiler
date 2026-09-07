## Regression CONTROL for #476, one arity BELOW the threshold: a generic fn with THREE comptime type
## parameters and three value parameters must still deliver every value argument to the parameter it
## was written for. This is the neighbour that works, and it is what makes the refusal one arity above
## it a measured boundary rather than a guess: at three type arguments the monomorphization machinery
## erases exactly three leading arguments, and the value arguments land at positions 0/1/2.
##
## The exit codes are all DISTINCT, so "42" is the only way to pass and no two failures share a code
## (AGENTS.md: a wrong value must never look like any other outcome; `0` in particular is both the
## defect's value and the commonest default):
##
##   42  correct  -- a=12, b=20, c=10, each in its own parameter
##    3  `a` arrived as 0     (a value parameter read an unwritten frame slot)
##    4  `b` arrived as 0
##    5  `c` arrived as 0
##    6  `a` holds what `b` was given   (the value list shifted one place down)
##    7  `b` holds what `c` was given   (the same shift, seen one parameter later)
##    8  `a` is neither 0 nor 20 and not 12 -- some other wrong value, not a shift
##    9  `b` is some other wrong value
##   10  `c` is some other wrong value
##
## A trap, a link failure or a refusal is none of the above and shows up as its own exit status.
pick3 := fn(A : type, B : type, C : type, a : A, b : B, c : C) -> u64 {
  if a == 0 { return 3 }
  if b == 0 { return 4 }
  if c == 0 { return 5 }
  if a == 20 { return 6 }
  if b == 10 { return 7 }
  if a != 12 { return 8 }
  if b != 20 { return 9 }
  if c != 10 { return 10 }
  return a + b + c
}

main := fn() -> u64 {
  return pick3(u64, u64, u64, 12, 20, 10)
}
