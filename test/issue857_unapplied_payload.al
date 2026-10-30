## Issue #857 / Comptime §10 + Types §6.2 — a bare type function as an enum variant PAYLOAD (the single payload of `B`)
## is not a `type`; it was accepted and compiled.
E := enum { B(Option), C }
main := fn() -> u64 { 0 }
## expect: reject "type function `Option` is not a type until it is applied" "at line 3 in issue857_unapplied_payload"
