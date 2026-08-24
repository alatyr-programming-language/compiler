## e2e — the ACCEPT sibling of `reject_unknown_attr_decl.al`. Declarations §2.3 closes only the
## layout machine levers (`@repr`…`@niche`); "other `@name` are comptime-function effectors (prelude
## or library, indistinguishable — CT-10)". So an attribute naming a DECLARATION in the program is a
## user-defined effector and MUST still be accepted, however unusual it looks — which is exactly why
## the unknown-attribute check cannot be a closed known-list in the parser.
nonzero := fn(x : i64) -> i64 {
  return x
}

@nonzero
X : i64 = 42

main := fn() -> i64 {
  return X
}
