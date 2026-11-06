## e2e — issue #1464: a FIELD ACCESS whose OWNER is a FUNCTION VALUE is refused at the access.
## A function value is one machine word, a code address (Functions §1.5); `.` selects a field, a tuple
## position `.N` or a UFCS call (Modules §2), and a code address has no field. Measured on the parent
## (`origin/main` `aab6ce1a`, native x86_64): check 0, build 0, and the program answered a fabricated 0.
f := fn() -> u64 { return 42 }
main := fn() -> u64 {
  g := f
  return g.a
}
## expect: reject "a function value has no field to name at line 8 in issue1464_fnval_field"
