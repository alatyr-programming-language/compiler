## e2e — Functions §1.4-A-5 (per-signature overload mangling): a bare STRING LITERAL argument must
## DISCRIMINATE an overload set, exactly as an integer / float literal already did. A `StrLit` carries
## no type span, so it used to match EVERY candidate parameter as a wildcard: `f("ok")` over the set
## `f(u64)` / `f(str)` stayed AMBIGUOUS, `overload_resolve_idx` answered -1, `emit_overload_suffix`
## emitted NOTHING, and the call site became the BARE label `<mod>__f` — which matches neither
## definition (`…__f__u64` / `…__f__str`) → `undefined reference to '<mod>__f'` from `ld`. A string
## literal can bind only to a `str` parameter, so the set now resolves to the `str` overload.
## Covers: the str overload alone (`b.len()` = 2), the int overload beside it (4), a str literal in a
## NON-first argument position (10 + 2 = 12), and a two-candidate set discriminated only by str-vs-int
## in argument 2 (3 * 4 = 12). 2 + 4 + 12 + 12 + 12 = 42.
f := fn(n : u64) -> u64 {
  return n
}
f := fn(s : str) -> str {
  return s
}
k := fn(a : u64, s : str) -> u64 {
  return a + s.len()
}
k := fn(a : u64, b : u64) -> u64 {
  return a * b
}
main := fn() -> u64 {
  b : str = f("ok")             ## the str overload — was an unresolved bare label at link
  a : u64 = f(4)                ## the int overload beside it still resolves
  return b.len() + a + k(10, "xy") + k(3, 4) + 12
}
