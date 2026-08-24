## e2e (FN-6 / the SysV FLOAT ABI — an INDIRECT call through a function VALUE that returns `f64`).
## SILENT MISCOMPILE regression: the parser keeps only the bare `fn` TOKEN for a fn-value type (the
## signature is discarded), so every `call *%rax` site captured its result with an unconditional
## `pushq %rax` — with NO return class. An `f64` result lives in %xmm0 under System V, so the value
## stack picked up whatever happened to sit in %rax and each of the shapes below evaluated to 0 in
## INTEGER context (`u64(h(10.5))` → 0, not 21). It was accidentally RIGHT only when the consumer was
## itself a float operation (%xmm0 still held the value) — see `fn_value_float_binop.al`.
##
## Every fn-value binding form is exercised, because each resolves the return type differently:
##   1. `h := dblf`            — bound to a NAMED fn (its own `Decl` supplies `-> f64`).
##   2. `g : fn(f64) -> f64`   — a DECLARED fn-value type (the signature is re-read from the source).
##   3. `lam := fn(x : f64)…`  — a LIFTED LAMBDA (`Expr::FnRef` → the synthetic decl's return type).
##   4. `constf(0)`            — an `f64` return from an all-INTEGER parameter list (no float rides in).
##   5. `appf(dblf, 1.0)`      — the fn value as a PARAMETER, called inside the callee.
## 21 + 10 + 7 + 2 + 2 = 42.
dblf := fn(x : f64) -> f64 { return x * 2.0 }
constf := fn(n : u64) -> f64 { return 2.5 }
appf := fn(f : fn(f64) -> f64, x : f64) -> u64 { return u64(f(x)) }

main := fn() -> u64 {
  ## 1. a fn value bound to a named fn, result consumed in INTEGER context — the shape that was 0.
  h := dblf
  a := u64(h(10.5))                ## 21
  ## 2. an explicitly typed fn-value binding, delivered into a declared `f64` local.
  g : fn(f64) -> f64 = dblf
  s : f64 = g(5.25)
  b := u64(s)                      ## 10
  ## 3. a lambda bound as a value, called indirectly.
  lam := fn(x : f64) -> f64 { x * 2.0 }
  c := u64(lam(3.5))               ## 7
  ## 4. a float RETURN out of an integer-parameter fn value.
  cf := constf
  d := u64(cf(0))                  ## 2
  ## 5. the fn value as a parameter of a higher-order fn.
  e := appf(dblf, 1.0)             ## 2
  return a + b + c + d + e
}
