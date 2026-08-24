## e2e — WHOLE-VALUE reassignment of a mutable ENUM global (`G = E.V(…)`). The single-word global-write
## path stored only the discriminant word, dropping the payload; now `emit_mut_global_whole_assign`
## copies `[disc, payload…]` whole. Init `E.A(1)`; after `G = E.B(42)` the match reads the new payload 42.
E := enum { A(u64), B(u64) }
mut G := E.A(1)
main := fn() -> u64 {
  G = E.B(42)
  match G { E.A(x) => x, E.B(y) => y }
}
