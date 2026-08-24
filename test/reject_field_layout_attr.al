## TYP layout surface: field-level layout attributes must fail loud while the compiler still uses the
## word-sized layout model. Silently accepting this would imply a byte-offset/alignment contract the lower
## does not implement yet.
S := struct {
  @align(16) value : u64
}

main := fn() -> u64 {
  s := S(value = 42)
  s.value
}
