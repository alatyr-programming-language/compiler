## Backend string emitters decode x-escapes instead of delegating their raw spelling to assemblers.
main := fn() -> u64 {
  print("\x41\xC3\xA9")
  42
}
