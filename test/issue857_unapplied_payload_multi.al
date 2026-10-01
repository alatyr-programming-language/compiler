## Issue #857 / Comptime §10 + Types §6.2 — the bare type function is the SECOND payload of a multi-payload variant; the
## parser records only the first payload, so this position is re-read from source.
E := enum { B(u64, Result(u64, u64), Option), C }
main := fn() -> u64 { 0 }
