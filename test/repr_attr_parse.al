## TYP layout surface: a decl-position `@repr(u8)` attribute with arguments must parse as a known
## layout marker even though the lean layout model remains word-sized. The attribute is intentionally
## no-op in this slice; construction and field read still run normally.
@repr(u8) Cell := struct { value : u64 }

main := fn() -> u64 {
  c := Cell(value = 42)
  c.value
}
