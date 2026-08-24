## e2e — atomic op on ONE FIELD of a mutable struct global. `ptr(S.x)` takes the address of the
## field's `.data` cell (`leaq LABEL + k*8(%rip)`), so `atomic::fetch_add` updates just that field.
## S.x starts 10; fetch_add(32) -> S.x = 42 (S.y untouched). Returns S.x = 42.
Pt := struct { x : u64, y : u64 }
mut S := Pt(x = 10, y = 0)
main := fn() -> u64 {
  p := ptr(S.x)
  atomic::fetch_add(p, 32, Ordering.seq_cst)
  S.x
}
