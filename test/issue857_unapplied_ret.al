## Issue #857 / Comptime §10 + Types §6.2 — a bare type function in the RESULT type position (`-> Option`) is not a
## `type`; it was accepted and compiled.
f := fn() -> Option { Option(u64).None }
main := fn() -> u64 { 0 }
