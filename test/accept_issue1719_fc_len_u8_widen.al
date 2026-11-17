## #1719 / spec#166, fail closed: the control. The program declaration under a prelude intrinsic's name
## provably accepts every argument, so the call stays a call of that declaration and answers its value.
## Shape: a `u8` local into `x : u64`, an implicit widening (Types §4.2/§4.3). Parent 8375ac06 answered 42.
len := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  n : u8 = 4
  len(n) + 38
}
## expect: run 42
