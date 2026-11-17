## #1719 / spec#166, fail closed: the control. The program declaration under a prelude intrinsic's name
## provably accepts every argument, so the call stays a call of that declaration and answers its value.
## Shape: a `u64` field read through `deref(p)` into `x : u64`. Parent 8375ac06 answered 42.
R := struct { n : u64 }
len := fn(x : u64) -> u64 { x }
g := fn(p : ptr(R)) -> u64 {
  len(deref(p).n) + 38
}
main := fn() -> u64 {
  r := R(n = 4)
  g(ptr(r))
}
## expect: run 42
