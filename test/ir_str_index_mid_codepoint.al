## e2e — #1576, #1550: `s[i]` on a `str` traps when byte `i` does not begin a code point (Stdlib
## appendix §3.6, OP-9: the bounds guard requires `i < s.byte_len()` and `(b & 0xC0) != 0x80`; I11).
## Byte 1 of `"é"` (0xC3 0xA9) is a continuation byte, in range, so only the boundary half of the
## guard can trap it. The index is a parameter, so no constant folds the read away, and the in-range
## boundary read before it answers normally, so the trap is the guard and not the function.
## Measured on the parent (`774ba852`): x86_64 answered 169 (no backend emitted the boundary check,
## #1550), the legacy aarch64 and riscv64 emitters exited 133 (`brk #0 // unsupported expr StrLit`)
## and legacy wasm 134.
at := fn(i : usize) -> u8 {
  s := "é"
  s[i]
}
main := fn() -> i32 {
  if at(0) != 195 { return 1 }
  i32(at(1))
}
## expect: trap
