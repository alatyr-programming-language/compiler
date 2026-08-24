## FFI (increment 3b, RECEIVING side): an exported `@abi(c)` Alatyr fn CALLED FROM C. `alt_add`
## carries `@export("alt_add") @abi(c)`, so its SysV prologue reads a,b from %rdi,%rsi (not the
## internal ABI). The C stub `drive` (test/ffi/recv_scalar.c) calls back into `alt_add(20, 22)`;
## `main` reaches it through the working @abi(c) CALL side. Round-trip Alatyr -> C -> Alatyr = 42.
@export("alt_add") alt_add := @abi(c) fn(a : i64, b : i64) -> i64 { a + b }

drive := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  return u64(drive())
}
