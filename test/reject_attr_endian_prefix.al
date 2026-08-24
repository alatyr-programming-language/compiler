## e2e (reject) — a TYPE-level `@endian(...)` (Types §8) has NO lowering: the lower implements only the
## per-FIELD endian swap (`field_endian_attr` → `bswap`/`rolw`), and there is no type-level swap.
## The VALUE-position spelling (`S := @endian(big) struct {…}`) has failed loud all along; the
## DECLARATION-PREFIX spelling below was consumed and dropped, so the struct was silently laid out in
## the NATIVE byte order — a wrong-bytes layout with no diagnostic, the forbidden outcome. Both
## spellings now reject located, pointing at the field-level lever that does work.
@endian(big)
S := struct { a : u32 }
main := fn() -> u64 {
  s := S(a = 1)
  return u64(s.a)
}
