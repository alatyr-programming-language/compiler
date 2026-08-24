## FFI: aggregate RETURN <= 16 bytes at an @abi(c) call (spec 150 §FN-9). mkpt/mkd live in
## test/ffi/struct_ret.c. SysV returns an all-integer struct Pt{a,b} in %rax:%rdx (INTEGER
## eightbytes) and an all-double struct D{x,y} in %xmm0:%xmm1 (SSE eightbytes). Each field is
## read back separately and combined by SUBTRACTION, so a swapped eightbyte (wrong result reg)
## yields a different exit code.
Pt := struct { a : i64, b : i64 }
D  := struct { x : f64, y : f64 }

mkpt := @extern @abi(c) fn(a : i64, b : i64) -> Pt   ## {a, b} -> %rax:%rdx
mkd  := @extern @abi(c) fn(x : f64, y : f64) -> D    ## {x, y} -> %xmm0:%xmm1

main := fn() -> u64 {
  p := mkpt(50, 20)      ## p.a = 50, p.b = 20  -> 50 - 20 = 30
  q := mkd(15.0, 3.0)    ## q.x = 15.0, q.y = 3.0 -> 15.0 - 3.0 = 12.0
  return u64(p.a - p.b) + u64(q.x - q.y)   ## 30 + 12 = 42
}
