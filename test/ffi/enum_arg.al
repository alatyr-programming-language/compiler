## FFI (increment 3c): passing an Alatyr enum (<= 16 bytes) to C. An enum is a {disc, payload}
## aggregate → SysV classes it into TWO INTEGER eightbytes (disc -> %rdi, payload -> %rsi), like a
## 16-byte integer struct (an enum has no float fields, so every eightbyte is INTEGER). useenum lives
## in test/ffi/enum_arg.c. E.B(43): disc = 1 (B is variant index 1), payload = 43; useenum returns
## payload - disc = 43 - 1 = 42 (validates BOTH eightbytes ride the correct integer register).
E := enum { A(i64), B(i64) }

useenum := @extern @abi(c) fn(e : E) -> i64

main := fn() -> u64 {
  return u64(useenum(E.B(43)))
}
