## Issue #269 residual — a direct qualified fallible value cannot occupy a scalar tail slot.
bad := fn() -> u64 { std::os::arena(4096) }
main := fn() -> u64 { return 42 }
