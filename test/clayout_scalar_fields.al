## CLAYOUT S4 — flat scalar struct fields use the Types §6.1 byte layout.
## The frozen seed is intentionally wrong here: it reserves one word per field, while the standard
## calculators already know natural byte alignment, padding, and tail rounding. The generic helper
## checks size/align and the second Field.offset through the same typeinfo path.
Tiny := struct { a : u8, b : u8 }
Triple := struct { a : u8, b : u8, c : u8 }
Mixed := struct { a : u8, b : u64 }

check := fn(T : type, want_size : u64, want_align : u64, want_second : u64) -> u64 {
  if size(T) != want_size { return 1 }
  if align(T) != want_align { return 2 }
  mut second : u64 = 0
  mut i : u64 = 0
  comptime for f in typeinfo(T).fields {
    if i == 1 { second = f.offset }
    i = i + 1
  }
  if second != want_second { return 3 }
  0
}

main := fn() -> u64 {
  if size(u8) != 1 { return 4 }
  if align(u8) != 1 { return 5 }
  if check(Tiny, 2, 1, 1) != 0 { return 6 }
  if check(Triple, 3, 1, 1) != 0 { return 7 }
  if check(Mixed, 16, 8, 8) != 0 { return 8 }
  return 42
}
