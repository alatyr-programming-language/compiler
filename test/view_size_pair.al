## P1-CLAYOUT S1 (spec Types §7): a `[T]` / `str` VIEW **is** the two-word {pointer, length} pair
## wherever it appears, and `[T].size()` / `str.size()` report **that pair** — 16 bytes on a 64-bit
## target, aligned as a pointer. Every line is chosen so the pre-S1 word model and the spec DISAGREE:
##   size(str) was 8 (the pointer alone) while a `str` FIELD already occupied 16 — the compiler
##     contradicted itself, and every `size(T)`-strided container was wrong at `T = str`;
##   a generic-INSTANCE type argument (`Slice(u8)`, `Option(u64)`) is a call-shaped type expression
##     with no bare type name, so the fold fell through to the SCALAR default 8 — a silent wrong
##     value for a 16-byte view (§7) and for a tag+payload `Option(u64)` (§6.2).
## `align(str)` is 8, NOT the size: a view is pointer-ALIGNED, so size and alignment differ.
## `size(Option(ptr(u64)))` stays 8 — `None` folds into the pointer's niche (§6.2), unchanged.
## The last check is the two-paths rule: the `size` fold and `typeinfo(...).offset` must agree.
## Returns 42 iff every line holds.
S := struct { s : str, n : u64 }

field1_offset := fn() -> u64 {
  mut total : u64 = 0
  mut i : u64 = 0
  comptime for f in typeinfo(S).fields {
    if i == 1 { total = f.offset }
    i = i + 1
  }
  total
}

main := fn() -> u64 {
  if size(str) != 16 { return 1 }
  if str.size() != 16 { return 2 }
  if align(str) != 8 { return 3 }
  if size(Slice(u8)) != 16 { return 4 }
  if size(Slice(u64)) != 16 { return 5 }
  if size([str; 2]) != 32 { return 6 }
  if size(Option(u64)) != 16 { return 7 }
  if size(Option(ptr(u64))) != 8 { return 8 }
  if size(S) != 24 { return 9 }
  if field1_offset() != str.size() { return 10 }
  if size(u64) != 8 { return 11 }
  if size(u8) != 1 { return 12 }
  return 42
}
