## #1719 / spec#166, fail closed: the control. The program declaration under a prelude intrinsic's name
## provably accepts every argument, so the call stays a call of that declaration and answers its value.
## Shape: a call returning `u64` into `x : u64`. Parent 8375ac06 answered 42.
len := fn(x : u64) -> u64 { x }
g := fn() -> u64 { 4 }
main := fn() -> u64 {
  len(g()) + 38
}
## expect: run 42
