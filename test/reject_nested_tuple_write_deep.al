## SOUNDNESS fail-loud (cardinal rule: never a silent miscompile) — the WRITE dual of
## reject_nested_tuple_deep. Component 1 of the outer tuple is `(1, (100, 200))` — position 1 within it
## is a MULTI-WORD nested tuple, NOT a single word. The nested `t.N.M = v` STORE only supports a FLAT
## single-word-position component (tcomp `ek == 6`); a store into a component with a multi-word position
## must be REJECTED (a loud panic), never mis-addressed. This fixture asserts the compiler fail-louds the
## write rather than silently corrupting a wider component. Workaround: bind the position through a local.
main := fn() -> u64 {
  mut t := (20, (1, (100, 200)))
  t.1.1 = 5
  u64(t.0)
}
