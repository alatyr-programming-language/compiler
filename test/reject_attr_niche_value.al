## e2e (reject) — the VALUE-position twin of `reject_attr_niche_prefix.al`. This one was the worst of
## the pair: the attribute was consumed, leaving `u64` as the declaration's VALUE expression, so the
## program compiled all the way through and died in the LINKER with `undefined reference to N` —
## loud, but at the wrong layer, with nothing pointing at the attribute that caused it. Types §8.
N := @niche(0) u64
main := fn() -> u64 {
  return 3
}
