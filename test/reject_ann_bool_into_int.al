## Types §4.2/§4.3 — `bool` is a distinct kernel type, not a numeric domain; its relation to an
## integer is the **numeric** class, which is ALWAYS explicit (`u64(b)`). An annotated binding whose
## initializer is a bool literal therefore does not conform (Declarations §3.1).
main := fn() -> u64 {
  x : u64 = true
  return x
}
