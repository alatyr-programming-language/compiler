## `no_abstractions` admits raw instruction intrinsics only over register/immediate operands. An
## `at(...)` addressing helper is still a structured operand calculation, so the checker must reject it
## even when it appears underneath an otherwise-admitted `movq(...)` raw instruction call.
@limits(no_abstractions)
main := fn() -> u64 {
  movq(rax, at(rbp, 8))
  syscall()
  return 0
}
