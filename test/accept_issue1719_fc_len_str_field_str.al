## #1719 / spec#166, fail closed: the control. The program declaration under a prelude intrinsic's name
## provably accepts every argument, so the call stays a call of that declaration and answers its value.
## Shape: a `str` field into `s : str`. Parent 8375ac06 answered 39 (the intrinsic's length 4, plus 35).
R := struct { s : str }
len := fn(s : str) -> u64 { 7 }
main := fn() -> u64 {
  r := R(s = "abcd")
  len(r.s) + 35
}
## expect: run 42
