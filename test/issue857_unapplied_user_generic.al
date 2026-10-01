## Issue #857 / Comptime §10 + Types §6.2 — a USER type function (`Box := fn(T : type) -> type {…}`) written bare in a
## parameter type is refused exactly like `Option`; `Box(u64)` stays valid.
Box := fn(T : type) -> type { return struct { v : T } }
f := fn(b : Box(u64), c : Box) -> u64 { b.v }
main := fn() -> u64 { 0 }
