## e2e — issue #1464, the TUPLE POSITION half: `.N` is a positional projection of a TUPLE only (Types
## §6.1), so `g.0` through a function value names no position either — the parser lowers it to
## `Index(base, Num(0))`, which is why it needs its own row beside the field rows. Measured on the
## parent (`origin/main` `aab6ce1a`, native x86_64): check 0, build 0, exit 0.
f := fn() -> u64 { return 42 }
main := fn() -> u64 {
  g := f
  return u64(g.0)
}
## expect: reject "a function value has no field to name at line 8 in issue1464_fnval_tuple_pos"
