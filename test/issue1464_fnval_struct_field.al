## e2e — issue #1464, a STRUCT FIELD of function type: `s.h.a` with `h : fn() -> u64`. Functions §1.5
## lets a function value be "stored (in a struct … field)"; the field's declared type decides that
## `s.h` is a code address, and a code address has no field. Measured on the parent (`origin/main`
## `f7011080`, native x86_64): check 0, build 0, and the program answered a fabricated 0.
f := fn() -> u64 { return 42 }
S := struct { h : fn() -> u64 }
main := fn() -> u64 {
  s := S(h = f)
  s.h.a
}
## expect: reject "a function value has no field to name at line 9 in issue1464_fnval_struct_field"
