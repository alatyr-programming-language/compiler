## e2e — issue #1464, the STORE path: `g.a = 4` through a function value. The parser keeps a field
## store as two name spans, so no expression walker sees the place and the read-side refusal cannot
## reach it (#693's finding, reused here). Measured on the parent (`origin/main` `aab6ce1a`, native
## x86_64): check 0, build 0, exit 3 with the store dropped.
f := fn() -> u64 { return 42 }
main := fn() -> u64 {
  mut g := f
  g.a = 4
  return 3
}
## expect: reject "a function value has no field to name at line 8 in issue1464_fnval_field_store"
