## Declarations §3.1 applies at MODULE scope too: a module-level annotated binding's initializer must
## be assignable to its declared type. `check_decl` checked the value expression but never against the
## annotation, so this passed while the local form already rejected.
G : u64 = "nope"
main := fn() -> u64 {
  return G
}
