## e2e/fmt — §4.2.3, second bullet: a binary-operator CHAIN that overflows 100 columns breaks BEFORE
## each of its operators, at the continuation indent (one level in), the operator BEGINNING the
## continuation line. fmt used to emit any chain on one line however wide.
##
## Three things are asserted at once. (1) The whole chain breaks, not just its outermost operator:
## `a + b + c` is `Bin(+, Bin(+, a, b), c)`, so a naive recursion would break only the outer `+` and
## leave `a + b` joined. (2) A chain that FITS is left alone — "a construct that fits at its indent is
## written on one line". (3) The break is semantics-PRESERVING: grammar §2.6 continues a line whose
## successor begins with a continuing token, so a re-parse must rebuild the identical left-leaning
## tree — this fixture's exit status is the check, since a re-grouped chain of `and`/`==` over these
## values changes the answer.
##
## The `total_sum` chain sits inside a CALL argument, which is the outermost-first rule at work: the
## call's argument list wraps first, and only then does the element's chain break — at the element's
## own (deeper) continuation indent.
wide := fn(v : u64) -> u64 {
  v
}

main := fn() -> u64 {
  alpha1 := 1
  alpha2 := 2
  alpha3 := 3
  alpha4 := 4
  alpha5 := 5
  alpha6 := 6
  small_sum := alpha1 + alpha2
  every_alpha_is_itself := alpha1 == 1 and alpha2 == 2 and alpha3 == 3 and alpha4 == 4 and alpha5 == 5 and alpha6 == 6
  total_sum := wide(alpha1 * 100000 + alpha2 * 200000 + alpha3 * 300000 + alpha4 * 400000 + alpha5 * 500000)
  if small_sum != 3 { return 1 }
  if not every_alpha_is_itself { return 2 }
  if total_sum != 5500000 { return 3 }
  42
}
