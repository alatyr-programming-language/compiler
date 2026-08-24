## CLAYOUT S2 — the when guard must use the same mixed-tuple size as size(...).
## The tuple is 16 bytes, so the <= 8 instance is rejected at the call site.
pick := fn(T : type, x : u64) -> u64 when size(T) <= 8 { x }

main := fn() -> u64 {
  pick((u64, u8), 42)
}
