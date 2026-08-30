## Failure-first on parent 92c0539810c7d4ead261ea459efe739e673770ad: build exited 14 after an unresolved
## raw-call symbol instead of enforcing the verification grant before emission.
main := fn() -> u64 {
  jmp(done)
  @label(done) asm("nop")
  return 42
}
