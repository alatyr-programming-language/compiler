## e2e — issue #774: a BARE NUMERIC `if` condition is refused (Control Flow §4: "A numeric scalar is
## not truthy … a numeric condition uses an explicit comparison yielding `bool` (`if n != 0 { … }`),
## never a bare `if n { … }`"). Measured on the parent (`origin/main` `2d6e05f4`, native x86_64):
## check 0, build 0, and the program took the branch on the word and answered 1.
main := fn() -> u64 {
  mut p : u64 = 10
  if p { return 1 }
  return 42
}
## expect: reject "a bare numeric condition is ill-formed at line 7 in issue774_if_numeric_cond"
