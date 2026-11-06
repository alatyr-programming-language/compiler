## e2e — issue #1464, the owner spelled DIRECTLY: the NAME of a function declaration in value position
## is that function's code address (Functions §1.5), so `f.a` names no field (Modules §2, Types §6.1).
## Measured on the parent (`origin/main` `aab6ce1a`, native x86_64): check 0, build 0, exit 0.
f := fn() -> u64 { return 42 }
main := fn() -> u64 {
  return f.a
}
## expect: reject "a function value has no field to name at line 6 in issue1464_fnval_field_global"
