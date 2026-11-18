## #1755 review B2 / spec#166, fail closed. The `_before` twin with the program's `len(x : u64)` declared
## after `main` (Declarations §7.1: the order does not matter). Under shadowing (spec#166 option A) the
## call is ill-formed; under overloading (option B) it answers 42. Until spec#166 is decided it stays
## refused, located at the call. #1755's first head (e43bebee, native x86_64 on omen) answered 42.
main := fn() -> u64 {
  s := "abcd"
  len(s) + 38
}
len := fn(x : u64) -> u64 { x }
## expect: reject "type mismatch" "at line 7"
