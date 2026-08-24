## §8 pointer-to-@packed (MMIO map, ek 7): a `ptr(PackedStruct)` reads each field at its PACKED byte
## offset THROUGH the pointer (not the word-sized offset). `Regs` packs a:u8@0, b:u16@1, c:u32@3 (no
## padding, size 7). `p := ptr(r)` binds p as a pointer-to-struct (ek 7); `deref(p).b` / `deref(p).c`
## must load b at byte 1 (movzwq) and c at byte 3 (movl) through %rax — a word-sized read would fetch
## offset 8 / 16 (past the 7-byte struct) and return garbage. Both spellings covered: `deref(p).f`
## (explicit) and the bare `p.f`. Returns 10 + 20 + 12 = 42 (each field read twice, halved values).
Regs := @packed struct { a : u8, b : u16, c : u32 }

main := fn() -> u64 {
  r := Regs(a = 10, b = 20, c = 12)
  if size(Regs) != 7 { return 1 }
  p := ptr(r)
  ## explicit deref(p).f spelling
  ra := u64(deref(p).a)
  rb := u64(deref(p).b)
  rc := u64(deref(p).c)
  if ra != 10 { return 2 }
  if rb != 20 { return 3 }
  if rc != 12 { return 4 }
  ## bare p.f spelling (same packed byte-offset read)
  ba := u64(p.a)
  bb := u64(p.b)
  bc := u64(p.c)
  if ba != 10 { return 5 }
  if bb != 20 { return 6 }
  if bc != 12 { return 7 }
  ba + bb + bc
}
