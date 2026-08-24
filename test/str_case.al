## e2e — base/str ASCII case folding (allocation-free, byte-level): `eq_ignore_ascii_case` (a
## case-insensitive `str` compare) plus the byte helpers `to_ascii_lower`/`to_ascii_upper` and the
## `is_ascii_*` classifiers. Returns 42 iff every case is exact: case-insensitive equal of differently-
## cased strings, non-equal on a real content difference, length mismatch rejected, byte fold round-trips,
## and the classifiers agree. Reached via the ambient `base::` root.
sm := base::str
main := fn() -> u64 {
  eq1 := sm::eq_ignore_ascii_case("FuncName", "funcname")   ## true
  eq2 := sm::eq_ignore_ascii_case("Hello", "HELLO")         ## true
  ne1 := sm::eq_ignore_ascii_case("abc", "abd")             ## false (content)
  ne2 := sm::eq_ignore_ascii_case("ab", "abc")              ## false (length)
  lo := sm::to_ascii_lower(65)                              ## 'A' -> 'a' == 97
  up := sm::to_ascii_upper(122)                             ## 'z' -> 'Z' == 90
  keep := sm::to_ascii_lower(48)                            ## '0' unchanged == 48
  cu := sm::is_ascii_upper(65)                              ## true
  cd := sm::is_ascii_digit(57)                              ## true ('9')
  ca := sm::is_ascii_alpha(48)                              ## false ('0')
  if eq1 and eq2 and (ne1 == false) and (ne2 == false)
     and lo == 97 and up == 90 and keep == 48
     and cu and cd and (ca == false) {
    return 42
  }
  return 7
}
