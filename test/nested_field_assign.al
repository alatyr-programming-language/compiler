## e2e (NESTED field mutation `o.i.v = e`). The field-assignment parser only handled a single level
## (`o.f = e`, `FieldAssign`); a nested path `o.i.v = 40` mis-parsed (the `.v` read as `=`). Now a
## `field_path_assign_starts` detector routes a ≥2-level field path through `p_field` into a nested
## `Field(Field(Var(o), i), v)` recorded as `FieldPathAssign`; the lower resolves the place's frame
## slot via `field_slot` (which walks the nested Field recursively → the down-growing inline layout)
## and stores. The nested-READ `o.i.v` already worked; this is the STORE dual. Exercises 2- and
## 3-level nesting + a mix with single-level fields.
A := struct { v : u64 }
B := struct { a : A, w : u64 }
C := struct { b : B, z : u64 }
main := fn() -> u64 {
  mut c : C = C(b = B(a = A(v = 0), w = 0), z = 0)
  c.b.a.v = 40      ## 3-level nested store
  c.b.w = 1         ## 2-level nested store
  c.z = 1           ## single-level (FieldAssign)
  ## read back via the nested-field READ path
  c.b.a.v + c.b.w + c.z   ## 40 + 1 + 1 = 42
}
