## e2e — issue #1464, the NESTED STORE through a function-typed struct field: `s.h.a = 4`. The parser
## keeps it as a field-path assignment, which the read walkers never see. Measured on the parent
## (`origin/main` `f7011080`, native x86_64): check 0 — only the lower refused it, at build, with a
## frame-slot message that names no owner kind.
f := fn() -> u64 { return 42 }
S := struct { h : fn() -> u64 }
main := fn() -> u64 {
  mut s := S(h = f)
  s.h.a = 4
  s.h()
}
## expect: reject "a function value has no field to name at line 9 in issue1464_fnval_struct_field_store"
