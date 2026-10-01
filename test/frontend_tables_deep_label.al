## e2e (#801 — Control Flow §7.1): a labeled loop nested 66 loops deep. The parser resolves `break name`
## against a stack of the enclosing loops' labels, and that stack held 64 frames: a loop past the 64th
## was not pushed, so its label was not in scope, `break inner` was read as a `break` carrying the value
## `inner`, and the build refused it. The stack now grows with the nesting.
## The innermost loop adds 42 and leaves through `break inner`; every loop around it leaves after its
## inner loop. Parent: the build refused it (rc 1, a `break` value into a non-value loop).
main := fn() -> u64 {
  mut r : u64 = 0
  loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { loop { @label(inner) loop { r = r + 42 ; break inner } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break } ; break }
  return r
}
