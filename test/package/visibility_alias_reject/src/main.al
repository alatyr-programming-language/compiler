## Modules §4.1 — an IMPORT/ALIAS binding is an ordinary declaration, and "what a binding may name
## follows the §3 visibility rule": a non-`pub` name of a NON-ANCESTOR module is not accessible. So
## the BINDING itself is the reject, whether or not the bound name is ever called.
f := geo::priv_fn
main := fn() -> u64 {
  return 42
}
