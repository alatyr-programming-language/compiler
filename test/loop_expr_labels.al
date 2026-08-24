## e2e — loop-as-expression `break <expr>` (Control Flow §7.2) + labeled `break name` / `continue name`
## (§2.1/§7.1). Exercises: a value-yielding `loop` bound to a local; a break-value produced from inside a
## conditional; two same-type break exits (common-type accept, §3); a labeled `break outer` exiting BOTH
## nested loops; a labeled `continue top` re-iterating the OUTER loop from an inner one. Returns 42 iff
## every observed value matches. Bare break/continue are covered by continue_stmt.al.
main := fn() -> u64 {
  ## 1. loop-as-expression: `break v` yields the loop's value
  x := loop { break 40 }                 ## x = 40

  ## 2. break-value produced from inside a conditional in the body
  mut i : u64 = 0
  y := loop {
    i = i + 1
    if i == 2 { break i }                ## y = 2
  }

  ## 3. two break-with-value exits of the SAME type (common-type accept)
  mut k : u64 = 0
  z := loop {
    k = k + 1
    if k == 1 { break 100 }
    break 200
  }                                      ## z = 100

  ## 4. labeled break: `break outer` exits BOTH loops at once
  mut hit : u64 = 0
  @label(outer) loop {
    loop {
      hit = hit + 1
      break outer                        ## leaves the inner AND the outer loop
    }
    hit = hit + 100                       ## unreachable
  }                                      ## hit = 1

  ## 5. labeled continue: `continue top` re-iterates the OUTER while from the inner one
  mut cnt : u64 = 0
  mut oi : u64 = 0
  @label(top) while oi < 3 {
    oi = oi + 1
    mut inner : u64 = 0
    while inner < 5 {
      inner = inner + 1
      if inner == 2 { continue top }      ## back to the outer guard (skips the tail below)
      cnt = cnt + 1                        ## runs once per outer pass (inner == 1) -> 3 total
    }
    cnt = cnt + 1000                        ## unreachable (continue top skips it)
  }                                        ## cnt = 3

  ## x=40, y=2, z=100, hit=1, cnt=3  ->  40 + 2 + 0 + 0 + 0 = 42
  40 + y + (z - 100) + (hit - 1) + (cnt - 3)
}
