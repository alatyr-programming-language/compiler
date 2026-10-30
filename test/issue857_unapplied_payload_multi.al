## Issue #857 / Comptime §10 + Types §6.2 — the bare type function is the SECOND payload of a multi-payload variant; the
## parser records only the first payload, so this position is re-read from source.
E := enum { B(u64, Result(u64, u64), Option), C }
main := fn() -> u64 { 0 }
## expect: reject "type function `Option` is not a type until it is applied" "at line 3 in issue857_unapplied_payload_multi"
