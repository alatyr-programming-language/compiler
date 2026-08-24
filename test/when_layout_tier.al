## CLAYOUT S2 — the generic when guard shares the layout tier with size(...).
Small := @packed struct { a : u8, b : u8 }

pick := fn(T : type, x : u64) -> u64 when size(T) <= 2 { x }

main := fn() -> u64 {
  pick(Small, 42)
}
