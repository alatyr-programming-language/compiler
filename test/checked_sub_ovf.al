## Checked-mode integer UNDERFLOW trap on `-` (I11 / CG-8): 0 - 1 borrows (unsigned); the
## compiler-emitted guard TRAPS (x86 subq+jnc+ud2 → 132). Native-width; unchecked wraps.
main := fn() -> u64 {
  ## `a` is ANNOTATED: an unannotated `a := 0` is the native SIGNED integer (Types §9.1, Declarations
  ## §3.4), so `a - 1` would not borrow; this fixture is about the u64 borrow.
  a : u64 = 0
  b := a - 1
  return b
}
