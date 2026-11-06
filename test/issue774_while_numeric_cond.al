## e2e — issue #774, the `while` half: §6 gives `while` the same condition as `if`, so a bare numeric
## loop condition is refused by the same class. Measured on the parent (`origin/main` `2d6e05f4`,
## native x86_64): check 0, build 0, and the loop spun on the word.
main := fn() -> u64 {
  mut n : u64 = 3
  while n { n -= 1 }
  return 42
}
## expect: reject "a bare numeric condition is ill-formed at line 6 in issue774_while_numeric_cond"
