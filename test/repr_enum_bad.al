## §8 @repr(T) representability — T MUST be an integer type (uN/iN/usize/bitsN, spec Types §8).
## `str` is not an integer type, so this @repr is a compile diagnostic: the build must FAIL LOUD
## (build_reject) rather than emit a binary with a meaningless tag.
Bad := @repr(str) enum { A, B }
main := fn() -> u64 {
  b := Bad.A
  match b { Bad.A => { return 1 } Bad.B => { return 2 } }
}
