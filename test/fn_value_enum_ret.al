## e2e (FN-6 — the ENUM return class of an INDIRECT call). An indirect call (`call *%rax` through a fn
## VALUE) had NO return class at all: the parser records only the bare `fn` token for a fn-value type,
## so the signature is lost. An ENUM result rides the two-register convention (disc/%rax + payload/%rdx),
## but the indirect call captured a single `pushq %rax`, so `match f(x)` dispatched on the raw word and
## bound its payload from slot 0 — a SILENT wrong value (this program returned 181 before the fix).
## The class is now recovered by source-scanning the fn type (`fnty_ret_span`) or, for a value bound
## straight to a named fn, from that callee's own `Decl` (`fnval_target_decl`).
## Covers all four shapes that must agree: the bare `f := mk` binding, the ANNOTATED `g : fn(u64) -> E`
## binding, a fn-value PARAM, and a MULTI-FIELD payload (`E.C(a, b)` — both payload registers).
## 10 + 11 + 12 + (4 + 5) = 42.
E := enum { A(u64), B(u64), C(u64, u64) }

mk := fn(x : u64) -> E { return E.A(x) }
mkc := fn(x : u64) -> E { return E.C(x, x + 1) }

## a fn-value PARAM (`f : fn(u64) -> E`) called indirectly and matched
via_param := fn(f : fn(u64) -> E, v : u64) -> u64 {
  mut o : u64 = 0
  match f(v) {
    E::A(n) => { o = n }
    E::B(n) => { o = 100 }
    E::C(n, m) => { o = 200 }
  }
  o
}

main := fn() -> u64 {
  ## 1. bare binding to a named fn — the return type comes from `mk`'s own decl
  f := mk
  mut r1 : u64 = 0
  match f(10) {
    E::A(n) => { r1 = n }
    E::B(n) => { r1 = 100 }
    E::C(n, m) => { r1 = 200 }
  }
  ## 2. an ANNOTATED fn-value binding — the return type is source-scanned out of `fn(u64) -> E`
  g : fn(u64) -> E = mk
  mut r2 : u64 = 0
  match g(11) {
    E::A(n) => { r2 = n }
    E::B(n) => { r2 = 100 }
    E::C(n, m) => { r2 = 200 }
  }
  ## 3. through a fn-value PARAMETER
  r3 := via_param(mk, 12)
  ## 4. a MULTI-FIELD payload through the same indirect call (payload words 0 and 1)
  h := mkc
  mut r4 : u64 = 0
  match h(4) {
    E::A(n) => { r4 = 300 }
    E::B(n) => { r4 = 400 }
    E::C(n, m) => { r4 = n + m }
  }
  r1 + r2 + r3 + r4
}
