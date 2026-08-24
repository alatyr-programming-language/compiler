## e2e (Types §9.4): a field read off a GENERIC struct-returning call — `id(P, …).b`, where
## `id(T, x) -> T` is called with `T = P` (a 2-word struct). `struct_ret_call` reports FALSE for a
## generic `-> T` return, so the single-`<call>.field` arm was skipped → the read fell to `pushq $0`:
## a SILENT 0 (`id(P, …).b` read 0 instead of 2). The binding path `r := id(P, …); r.b` already
## worked via `gen_ret_struct_span`; `call_chain_place` now consults that SAME resolver for the
## direct `<call>.field` form. = 2.
P := struct { a : u64, b : u64 }
id := fn(T : type, x : T) -> T { return x }
main := fn() -> u64 {
  return id(P, P(a = 40, b = 2)).b
}
