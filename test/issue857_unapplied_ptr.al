## Issue #857 / Memory §4.1 — the builtin `ptr` constructor needs its pointee: a bare `ptr` in an enum
## variant payload was accepted (a bare `ptr` parameter or local annotation already was refused).
E := enum { B(ptr), C }
main := fn() -> u64 { 0 }
