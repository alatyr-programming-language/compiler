## #1719 / spec#166, fail closed: the control. The program declaration under a prelude intrinsic's name
## provably accepts every argument, so the call stays a call of that declaration and answers its value.
## Shape: `ptr(b)` of a `u8` local into `p : ptr(u8)`. Parent 8375ac06 refused it at build.
len := fn(p : ptr(u8)) -> u64 { u64(deref(p)) }
main := fn() -> u64 {
  b : u8 = 2
  len(ptr(b)) + 40
}
## expect: run 42
