## e2e (FN-6/FN-10 — every SOUND way to reach a function value's call). A call's CALLEE is a bare
## NAME: an fn value reached through an INDIRECTION (an array element, a call result, a field) must be
## BOUND to a name first, and `<expr>(args)` is a fail-loud parse reject (see
## `reject_call_index_callee` / `reject_call_call_callee` / `reject_call_paren_callee`). This fixture
## LOCKS the working side of that line — the indirect-call machinery itself is sound, only the parse of
## a non-name callee is missing — so a later fix that teaches the parser `fs[0](x)` must keep every
## form here byte-identical:
##   1. an fn-value ARRAY element bound then called       `g := fs[0]` ; `g(9)`
##   2. the same bound INSIDE A LOOP over a runtime index `h := fs[i]` ; `h(3)`
##   3. an fn value PASSED to a higher-order fn + called there
##   4. an fn value RETURNED from a fn, bound, then called
##   5. a UFCS method call on a value receiver                    `v.dbl()`
##   6. a LAMBDA bound to a name then called
##   7. fn-value EQUALITY (two names for one code address compare equal)
## Each step contributes 10:  7 * 10 = 70.
add1 := fn(x : u64) -> u64 { return x + 1 }
dbl := fn(x : u64) -> u64 { return x * 2 }
apply := fn(f : fn(u64) -> u64, v : u64) -> u64 { return f(v) }
mk := fn() -> fn(u64) -> u64 { return add1 }

main := fn() -> u64 {
  fs : [fn(u64) -> u64; 2] = [add1, dbl]
  ## 1. array element -> name -> call. add1(9) = 10.
  g := fs[0]
  r1 := g(9)
  ## 2. the same through a RUNTIME index, rebound each iteration. add1(3) + dbl(3) = 4 + 6 = 10.
  mut acc : u64 = 0
  mut i : u64 = 0
  while i < 2 {
    h := fs[i]
    acc = acc + h(3)
    i = i + 1
  }
  ## 3. passed to a higher-order fn and called there. dbl(5) = 10.
  r3 := apply(dbl, 5)
  ## 4. returned from a fn, bound, then called. add1(9) = 10.
  k := mk()
  r4 := k(9)
  ## 5. a UFCS method call — the receiver becomes argument 0. dbl(5) = 10.
  v : u64 = 5
  r5 := v.dbl()
  ## 6. a lambda bound to a name, then called. 6 + 4 = 10.
  lam := fn(n : u64) -> u64 { return n + 4 }
  r6 := lam(6)
  ## 7. fn-value equality — `g` holds `add1`'s code address.
  mut r7 : u64 = 0
  if g == add1 { r7 = 10 }
  return r1 + acc + r3 + r4 + r5 + r6 + r7
}
