## `match cs[i]` directly over an ENUM-element array element (the index dual of the
## struct-enum-field match). Previously the Index scrutinee fell to the integer path and dispatched
## on a garbage discriminant with all-zero arm literals (silent no-match). Now try_index_enum_scrut
## materializes element i's enum words into the match scratch. Elements sum to 40 + 2 = 42.
Col := enum { R, G(u64), B }
main := fn() -> u64 {
  cs := [Col.G(40), Col.G(2)]
  mut acc : u64 = 0
  for i in 0..2 {
    match cs[i] {
      Col::R => {}
      Col::G(x) => { acc = acc + x }
      Col::B => {}
    }
  }
  return acc
}
