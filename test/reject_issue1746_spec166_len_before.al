## #1755 review B2 / spec#166, fail closed. A program `len(x : u64)` declared before `main`, called with
## a `str`. Under shadowing (spec#166 option A) the call is ill-formed; under overloading (option B) it
## falls to the prelude's generic `len` and answers 42. The spec has not decided, so the call stays
## refused, located at the call, as it was before #1746 made the checker see every declaration.
## #1755's first head (e43bebee, native x86_64 on omen) counted the library's `len` overloads beside
## this one, skipped the check and answered 42, choosing option B.
len := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  s := "abcd"
  len(s) + 38
}
## expect: reject "type mismatch" "at line 10"
