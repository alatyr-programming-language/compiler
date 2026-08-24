## forget(x) as the TERMINAL use (the corpus shape: discharge then return an unrelated value) — no
## later mention of x, so check ACCEPTS. Guards against a false positive in the use-after-forget check.
main := fn() -> u64 {
  x := 5
  forget(x)
  0
}
