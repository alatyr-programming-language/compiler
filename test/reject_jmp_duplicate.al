## Failure-first on parent 92c0539810c7d4ead261ea459efe739e673770ad: build exited 14 after unresolved
## raw-call/linker handling (and stale string-label output), with no source-located semantic diagnostic.
main := fn() -> u64 {
  unchecked {
    @label(done) asm("nop")
    @label(done) asm("nop")
    jmp(done)
  }
  return 42
}
