## Issue #857 / Memory §4.1 — a bare `ptr` as a struct FIELD type is no type; it was accepted.
N := struct { v : u64, p : ptr }
main := fn() -> u64 { 0 }
