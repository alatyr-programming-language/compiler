## Issue #803 / Types §9.1 — a written negative element below a signed element type's minimum:
## `-129` does not fit `i8`. The parent accepted this binding.
main := fn() -> u64 {
  a : [i8; 3] = [-128, 127, -129]
  return u64(a[1])
}
