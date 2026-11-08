## e2e — issue #1464, a PARAMETER of function type: `h.a` on `h : fn() -> u64`. The owner's kind is
## decided by its DECLARED type, not by how the value was spelled: Functions §1.5 lets a function value
## be "passed", and passed it is still one code address with no field. Measured on the parent
## (`origin/main` `f7011080`, native x86_64): check 0, build 0, and the program answered a fabricated 0.
f := fn() -> u64 { return 42 }
take := fn(h : fn() -> u64) -> u64 { h.a }
main := fn() -> u64 { take(f) }
## expect: reject "a function value has no field to name at line 6 in issue1464_fnval_param_field"
