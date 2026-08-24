## build_reject — a whole-value assignment to a mutable bare-str global (`S = "…"`). The bare str-global
## READ path is itself broken (`.len` reads 0), so no correct observable result exists; the lower FAILS
## LOUD rather than emit a word-copy against a broken read. (A str FIELD of a struct global works.)
mut S := "hi"
main := fn() -> u64 {
  S = "worldww"
  S.len
}
