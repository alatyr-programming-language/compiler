## e2e (FN-10 — the ENUM return class of an indirect call through a fn-VALUE STRUCT FIELD). `o.g(x)`
## desugars to the UFCS shape `Call(g, [o, x])` and is routed through `o`'s field slot (`call *%rax`).
## Like the bare fn-value call it carried NO return class, so `match o.g(x)` dispatched on the raw
## pushed word and read its payload from slot 0 — a SILENT wrong value (this program returned 0).
## The field's DECLARED type text IS a real `fn(…) -> R` span (a field type is kept verbatim), so the
## return type reads straight off it; `emit_enum_value` then routes the member call through the field
## exactly as the scalar site does (receiver erased, `nargs - 1` value args).
## The struct-field indirect call is x86_64-only GAS, like `fn_value_type` → run_x86.
## 30 + 12 = 42.
E := enum { A(u64), B(u64) }

mka := fn(x : u64) -> E { return E.A(x) }
mkb := fn(x : u64) -> E { return E.B(x) }

H := struct { g : fn(u64) -> E }

main := fn() -> u64 {
  h := H(g = mka)
  mut r1 : u64 = 0
  match h.g(30) {
    E::A(n) => { r1 = n }
    E::B(n) => { r1 = 100 }
  }
  k := H(g = mkb)
  mut r2 : u64 = 0
  match k.g(12) {
    E::A(n) => { r2 = 200 }
    E::B(n) => { r2 = n }
  }
  r1 + r2
}
