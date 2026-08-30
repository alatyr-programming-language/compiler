## Failure-first on parent 92c0539810c7d4ead261ea459efe739e673770ad: build exited 14 after an unresolved
## raw-call symbol, with no source-located semantic diagnostic.
main := fn() -> u64 {
  unchecked {
    jmp(missing)
  }
  return 42
}
