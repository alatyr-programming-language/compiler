## MOD §7 (`@extern`): a bodyless `name := @extern("sym") fn(…)` import — calls to it resolve to the
## EXTERNAL symbol `sym` (§7.2), and no body is emitted for it. Paired here with `@export("sym")` so the
## import links to an internally-exported definition (self-contained): `main → consumer` routes to
## `shared_impl`, which `producer` exports → 42.
@export("shared_impl") producer := fn() -> u64 {
  return 42
}

consumer := @extern("shared_impl") fn() -> u64

main := fn() -> u64 {
  return consumer()
}
