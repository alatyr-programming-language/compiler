## build_reject — Stdlib §2.6: a bare comparison over a by-value TUPLE / ARRAY whose components are
## NOT single-word integers must FAIL LOUD.
##
## What was silently wrong: `["ab", "cd"] == ["ab", "ce"]` fell through to the scalar `cmpq` and
## compared word 0 — the first element's string POINTER — so this program returned 1 (EQUAL). The
## componentwise word compare the lower now emits for integer components is NOT the answer here: a
## `str` component is a 2-word `{ptr, len}` view, so word-wise equality would compare string IDENTITY
## rather than string CONTENT. The same holds for float components (NaN and ±0 are word-wise wrong),
## and for struct / enum / nested-tuple components. `base::derive::eq` is the right vehicle for those,
## but its instance is keyed by a TYPE SPAN and an inferred tuple/array local has no type text in the
## source to key on — so the construct fails loud until that is solved.
main := fn() -> u64 {
  a := ["ab", "cd"]
  b := ["ab", "ce"]
  if a == b { return 1 }
  return 42
}
