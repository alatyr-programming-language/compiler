## e2e — a DECLARATION-PREFIX `@packed` (Declarations §2.3 / Grammar §3.2) enables the FIELD-level
## byte-layout attributes inside the body, exactly like the value-position spelling.
##
## The layout half of the prefix spelling is honoured by `lower_layout::_decl_prefix_attr`, but the
## PARSER's own gate on `@offset`/`@align`/`@endian` fields read only the value-position flag
## (`sm_packed`), so this program was REJECTED — "field-level @offset(N)/@align(N)/@endian(...)
## require a @packed struct" — while its value-position twin below compiled. Legal code turned away
## by the half of the compiler that had not been told.
##
## `hi` and `lo` are both placed at byte 0 (an explicit overlap, Types §8): the literal writes them in
## declaration order, so `lo` (written last) wins and reading `hi` back yields 42, not the 11 it was
## constructed with. `tail` then sits at byte 4. Identical checks on both spellings, so neither can
## pass by being wrong the same way.
@packed
Pfx := struct { hi : u32, @offset(0) lo : u32, tail : u8 }
Val := @packed struct { hi : u32, @offset(0) lo : u32, tail : u8 }

main := fn() -> u64 {
  if Pfx.size() != 5 { return 1 }
  if Val.size() != 5 { return 2 }
  p := Pfx(hi = 11, lo = 42, tail = 7)
  if u64(p.hi) != 42 { return 3 }
  if u64(p.lo) != 42 { return 4 }
  if u64(p.tail) != 7 { return 5 }
  v := Val(hi = 11, lo = 42, tail = 7)
  if u64(v.hi) != 42 { return 6 }
  if u64(v.tail) != 7 { return 7 }
  return 42
}
