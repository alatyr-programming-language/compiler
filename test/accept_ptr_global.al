## Returning the address of a GLOBAL (not a fn-scoped local) is fine — the global persists. Guards the
## dangling check against a false positive.
g : u64 = 7
f := fn() -> ptr(u64) {
  ptr(g)
}
main := fn() -> u64 { 0 }
