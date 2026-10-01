## Issue #857 / Comptime §10 + Types §6.2 — `Option` is a type function; only its application `Option(T)` is a
## `type`. A bare `Option` as a PARAMETER type was accepted and compiled.
f := fn(o : Option) -> u64 { 0 }
main := fn() -> u64 { 0 }
