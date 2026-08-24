## @abi(naked) raw-asm fn (spec ch.80): NO prologue/epilogue — the body is raw machine instructions
## over the System V registers, closed by an explicit `ret()`. `add2` reads its args from %rdi/%rsi
## (the System V integer arg registers), leaves the sum in %rax (the scalar return register), and
## `ret`s on the caller's exact stack. `main` calls it the ordinary way; add2(40, 2) -> 42.
add2 := @abi(naked) fn(a : i64, b : i64) -> i64 {
  movq(rax, rdi)
  addq(rax, rsi)
  ret()
}
main := fn() -> u64 {
  add2(40, 2)
}
