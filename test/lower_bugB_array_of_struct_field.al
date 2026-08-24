## Regression: the LOCAL `[Struct; N]` field is now correctly sized + accessed (see
## `struct_array_of_struct_field.al`, run 42). What REMAINS fail-loud is the POINTER-COMPOUND
## `deref(p).cells[i].m` — a struct array FIELD indexed through a NON-local root: the element-address
## math only composes a `Var`-rooted `s.cells[i]`, so this is REJECTED with a controlled `panic("selfhost:
## …")` rather than a silent-0 / SIGILL. Must be a controlled compile-time panic. `alatyr build` rejects
## loudly. Workaround: bind the pointee to a local first (`mut q := deref(p); q.cells[i].m`).
Cell := struct { m : u64, n : u64 }
Box := struct { pad : u64, cells : [Cell; 3] }
main := fn() -> u64 {
  mut b := Box(pad=1, cells=[Cell(m=10,n=1), Cell(m=20,n=2), Cell(m=30,n=3)])
  p := ptr(mut b)
  u64(deref(p).cells[2].m)
}
