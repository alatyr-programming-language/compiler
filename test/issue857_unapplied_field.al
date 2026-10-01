## Issue #857 / Comptime §10 + Types §6.2 — a bare type function as a struct FIELD type is not a `type`. The
## well-formed first field keeps the diagnostic on the second one.
N := struct { v : u64, o : Option }
main := fn() -> u64 { 0 }
