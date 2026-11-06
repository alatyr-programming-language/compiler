## Nested tuple element WRITE `t.N.M = v` (write-dual of the two-level read).
## `t` is a MIXED tuple: component 0 is a scalar (the NEIGHBOUR); component 1 is a
## FLAT single-word tuple `(99, 88)`. Overwrite BOTH words of component 1 — `t.1.0`
## (store at offset 0) and `t.1.1` (store at offset +8) — then read them all back.
## Neighbour-corruption check: t.0 (10) must survive both writes to component 1.
## 10 + 20 + 12 = 42.
main := fn() -> u64 {
  mut t := (10, (99, 88))
  t.1.0 = 20
  t.1.1 = 12
  u64(t.0 + t.1.0 + t.1.1)
}
