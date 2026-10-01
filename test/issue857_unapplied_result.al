## Issue #857 / Comptime §10 + Types §6.2 — `Result` written bare as a struct field, nested inside `ptr(…)`'s argument
## list, is refused; the unapplied name is located at the `Result` itself.
N := struct { p : ptr(Result), v : u64 }
main := fn() -> u64 { 0 }
