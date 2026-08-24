## FFI: INTEGER-class struct-by-value args at an @abi(c) call. sumpt/useone live in
## test/ffi/struct_arg.c. SysV classes a 16-byte all-integer struct into TWO integer regs
## (p.x -> rdi, p.y -> rsi) and a 1-eightbyte struct into ONE (rdi). sumpt returns p.x - p.y
## (ORDER-SENSITIVE: a swapped rdi/rsi would give a wrong exit), useone returns o.v.
Pt  := struct { x : i64, y : i64 }
One := struct { v : i64 }

sumpt  := @extern @abi(c) fn(p : Pt) -> i64
useone := @extern @abi(c) fn(o : One) -> i64

main := fn() -> u64 {
  p := Pt(x = 50, y = 15)   ## sumpt -> 50 - 15 = 35
  o := One(v = 7)           ## useone -> 7
  return u64(sumpt(p) + useone(o))   ## 35 + 7 = 42
}
