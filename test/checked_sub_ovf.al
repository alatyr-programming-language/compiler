## Checked-mode integer UNDERFLOW trap on `-` (I11 / CG-8): 0 - 1 borrows (unsigned); the
## compiler-emitted guard TRAPS (x86 subq+jnc+ud2 → 132). Native-width; unchecked wraps.
main := fn() -> u64 {
  a := 0
  b := a - 1
  return b
}
