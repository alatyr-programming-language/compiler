## FFI (increment 3c): passing an Alatyr `str` to C. A str is a 2-word {ptr, len} aggregate → SysV
## classes it into TWO INTEGER eightbytes (ptr -> %rdi, len -> %rsi), exactly like a 16-byte integer
## struct. strlen42 lives in test/ffi/str_arg.c. The literal " 123456789" has len 10, first byte 0x20
## (space = 32): strlen42 returns len + ptr[0] = 10 + 32 = 42 (validates BOTH eightbytes ride correctly).
strlen42 := @extern @abi(c) fn(s : str) -> i64

main := fn() -> u64 {
  return u64(strlen42(" 123456789"))
}
