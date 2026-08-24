## SOUNDNESS fail-loud (cardinal rule: never a silent miscompile). Component 1 of the outer tuple is
## `(1, (100, 200))` — position 1 within it is a MULTI-WORD nested tuple `(100, 200)`, NOT a single word.
## The nested `t.N.M` value-read only supports a FLAT single-word-position component (tcomp `ek == 6`);
## a component with a multi-word position must be REJECTED (a loud panic), never mis-read: `t.1.1` as a
## one-word `+M*8` load would truncate `(100,200)` to its first word AND (with the earlier scalar) is a
## deferred layout. This fixture asserts the compiler now fail-louds it (build_reject) rather than the
## former silent miscompile (returned 120). Workaround: bind the multi-word position through a named local.
main := fn() -> u64 {
  t := (20, (1, (100, 200)))
  y := t.1.1
  return y.0 + y.1
}
