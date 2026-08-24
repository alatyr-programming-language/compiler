## Modules §4.1.1 — a listed member projection `(a, b) := M` binds each listed name to `M::<name>`,
## and "a listed name that is not a `pub` member of `M` (subject to the §3 visibility rule) is a
## compile error". `main` is a sibling of `geo`, so `priv_fn` is not one of its `pub` members.
(priv_fn) := geo
main := fn() -> u64 {
  return 42
}
