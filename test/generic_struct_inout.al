## e2e (lean-lower: field access + in-out write-back on a GENERIC-struct DIRECT param). A param
## `in out q : Box(T)` (Box a generic struct) mis-lowered: `bind_param` resolved the struct decl by
## the WHOLE annotation span `Box(T)`, which `struct_decl_of` streq's against decl names → no match →
## the param never bound as a struct → `q.a` computed a field offset of -1 (a malformed `--8(%rbp)`).
## Fix: `base_type_name` strips the generic type-argument application `Box(T)` → `Box` for the decl +
## field resolution (all word-sized instances share one layout). `bumpg` twice: a += 1 (→2), d += 20
## (→40); 2 + 40 = 42. Needed for the allocator-borne containers' `in out v : Vec(T)` mutators.
Box := fn(T : type) -> type { struct { a : u64, b : u64, c : u64, d : u64 } }
bumpg := fn(T : type, in out q : Box(T)) {
  q.a = q.a + 1
  q.d = q.d + 20
}
main := fn() -> u64 {
  mut q := Box(u64)(a = 0, b = 0, c = 0, d = 0)
  bumpg(u64, q)
  bumpg(u64, q)
  q.a + q.d
}
