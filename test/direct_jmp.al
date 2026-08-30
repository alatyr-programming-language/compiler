## Failure-first on parent 92c0539810c7d4ead261ea459efe739e673770ad: the frozen seed's ordinary-call
## lowering reached ld and exited 14 on an unresolved direct_jmp__jmp symbol instead of transferring.
main := fn() -> u64 {
  unchecked {
    jmp(done)
    return 5
    @label(done) asm("nop")
  }
  return 42
}
