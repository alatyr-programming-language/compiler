## FFI (increment 3b): an exported `@abi(c)` fn taking a <=16B INTEGER struct BY VALUE from C.
## SysV classes `Pt{i64,i64}` into two integer regs (p.x=%rdi, p.y=%rsi); `alt_sumpt` returns
## p.x - p.y in %rax. The C stub `drivep` calls `alt_sumpt({50,15})` = 35, then adds 7 = 42.
Pt := struct { x : i64, y : i64 }

@export("alt_sumpt") alt_sumpt := @abi(c) fn(p : Pt) -> i64 { p.x - p.y }

drivep := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  return u64(drivep())
}
