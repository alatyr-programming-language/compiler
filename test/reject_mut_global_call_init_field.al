## e2e BUILD-REJECT (correct-or-trap, D69) — the `mut` half of `reject_global_call_init`. A `mut`
## module-level global initialized by a runtime CALL returning an aggregate DOES get `.data` storage,
## but nothing runs before `_start`, so the call never happens and that storage stays ZEROED: reading
## a FIELD of it silently returned 0 instead of the initializer's value (here 11 instead of 5 + 6).
## The build now rejects the FIELD READ. The DECLARATION itself stays legal — zeroed storage whose
## ADDRESS is taken is the shipped global-`Mutex` idiom (`mut MTX := std::sync::new(u64, 0)` in
## `mutex_basic`, an all-zero initial state) — so the guard sits at the read site, not the binding.
S := struct { a : u64, b : u64 }
mk := fn() -> S {
  return S(a = 5, b = 6)
}
mut G := mk()
main := fn() -> u64 {
  return u64(G.a + G.b)
}
