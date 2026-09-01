## Issue #269 residual — a direct qualified fallible value cannot occupy a named-struct return slot.
bad := fn() -> std::io::File { return std::io::open("", 0) }
main := fn() -> u64 { return 42 }
