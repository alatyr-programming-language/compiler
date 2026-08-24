## The module-scope guard against a false reject: every conforming module-level annotated shape the
## rule sits next to must stay accepted.
G : bool = true
K : str = "ok"
N : u64 = 7
main := fn() -> u64 {
  if G { return N + K.len() }
  return 0
}
