## Checked-mode integer OVERFLOW trap on `*` (I11 / CG-8): 6148914691236517206 * 3 = 2^64 + 2
## overflows u64; the compiler-emitted guard TRAPS (x86 mulq+jnc+ud2 → 132). unchecked wraps to 2.
main := fn() -> u64 {
  a := 6148914691236517206
  b := a * 3
  return b
}
