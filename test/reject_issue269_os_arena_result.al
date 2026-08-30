## Issue #269 / Functions §3.1–§3.2 / Stdlib §6 — a direct qualified Result
## return value is not the OsArena payload expected by std::os::free.
main := fn() -> u64 {
  std::os::free(std::os::arena(4096))
  return 42
}
