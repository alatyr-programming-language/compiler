## e2e — `break` inside a `for` loop (bare, in-a-conditional, labeled) + labeled `continue` out of a
## `for` (Control Flow §7). A bare `break` inside a `for` had NO real target (the `for` emit tracked only
## its continue label, never `cx.brk`), so it jumped to the `-1` no-loop sentinel → `jmp .L-1`, an
## undefined label that LINK-ERRORED. This exercises every `for`-break/continue shape and returns 42.
main := fn() -> u64 {
  ## 1. bare break in a for — exits at the first iteration
  mut a : u64 = 0
  for i in 0..10 { a = i; break }                      ## a = 0

  ## 2. break inside an `if` inside a for — sum 0..5 then break at 6
  mut b : u64 = 0
  for i in 0..100 { if i == 6 { break } b = b + i }    ## b = 0+1+2+3+4+5 = 15

  ## 3. labeled `break o` exiting a labeled OUTER for from an inner for (exits BOTH)
  mut c : u64 = 0
  @label(o) for i in 0..5 {
    for j in 0..5 { c = c + 1; break o }               ## exits both fors — c = 1
    c = c + 100                                          ## unreachable
  }

  ## 4. labeled `break of` exiting an outer for from an inner WHILE
  mut d : u64 = 0
  @label(of) for i in 0..3 {
    mut k : u64 = 0
    while k < 10 { k = k + 1; d = d + 1; if k == 2 { break of } }   ## exits the for — d = 2
    d = d + 1000                                         ## unreachable
  }

  ## 5. for-continue (regression guard): skip odds in 0..6 -> 0+2+4 = 6
  mut e : u64 = 0
  for i in 0..6 { if i % 2 == 1 { continue } e = e + i }   ## e = 6

  ## 6. labeled `continue ot` re-iterating an outer for from an inner for
  mut f : u64 = 0
  @label(ot) for i in 0..3 {
    for j in 0..5 { if j == 1 { continue ot } f = f + 1 }   ## once per outer pass (j==0) -> 3
    f = f + 500                                          ## unreachable
  }

  ## a=0 b=15 c=1 d=2 e=6 f=3  ->  42 iff all match
  42 + a + (b - 15) + (c - 1) + (d - 2) + (e - 6) + (f - 3)
}
