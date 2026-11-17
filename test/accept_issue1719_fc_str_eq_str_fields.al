## #1719 / spec#166, fail closed: the control. The program declaration under a prelude intrinsic's name
## provably accepts every argument, so the call stays a call of that declaration and answers its value.
## Shape: two `str` fields into `str_eq(a : str, b : str)`. Parent 8375ac06 answered 7 (the intrinsic
## compared the unequal texts).
R := struct { a : str, b : str }
str_eq := fn(a : str, b : str) -> bool { a.len == b.len }
main := fn() -> u64 {
  r := R(a = "abcd", b = "wxyz")
  if str_eq(r.a, r.b) { return 42 }
  7
}
## expect: run 42
