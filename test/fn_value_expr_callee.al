## e2e (FN-6 / spec §7 function values) — a call through an EXPRESSION CALLEE. `Expr::Call` carries its
## callee as a NAME SPAN, so `fs[0](10)` used to be a fail-loud parse reject (and before that a SILENT
## MISCOMPILE: the trailing `(10)` was dropped and `add1`'s CODE ADDRESS leaked out as the result). It
## now lowers through the existing indirect-call convention: the callee expression is evaluated to a
## code pointer and `call *%rax`'d, with the fn TYPE recovered from the place's declaration so the call
## is ARITY-checked (`reject_call_expr_callee_arity`) and its return CLASS policed
## (`reject_call_expr_callee_ret`). The forms still rejected are locked by `reject_call_index_callee`
## (an element callee with no named root), `reject_call_call_callee` (a call RESULT callee) and
## `reject_call_paren_callee` (a wrong arity through a parenthesized name).
##
##   1. an fn-value ARRAY element called directly          `fs[0](9)`
##   2. the sibling element                                `fs[1](5)`
##   3. a RUNTIME index, in a loop                         `fs[i](3)`
##   4. the element PARENTHESIZED                          `(fs[0])(9)`
##   5. a parenthesized bare NAME (an ordinary call)       `(add1)(9)`
##   6. a struct FIELD array, at a RUNTIME index           `t.fs[j](3)`
##   7. a TWO-parameter fn value                           `ops[0](4, 6)`
##   8. an expression-callee call in ARGUMENT position     `id(ops[1](14, 4))`
##   9. an expression-callee call NESTED in its own args   `ops[0](ops[1](7, 4), 7)`
##  10. a FLOAT parameter (the SSE argument class)         `gs[0](10.5)`
## Each step contributes 10:  10 * 10 = 100.
add1 := fn(x : u64) -> u64 { return x + 1 }
dbl := fn(x : u64) -> u64 { return x * 2 }
add := fn(a : u64, b : u64) -> u64 { return a + b }
sub := fn(a : u64, b : u64) -> u64 { return a - b }
id := fn(x : u64) -> u64 { return x }
trunc := fn(x : f64) -> u64 { return u64(x) }

Tbl := struct { fs : [fn(u64) -> u64; 2] }

main := fn() -> u64 {
  fs : [fn(u64) -> u64; 2] = [add1, dbl]
  ops : [fn(u64, u64) -> u64; 2] = [add, sub]
  gs : [fn(f64) -> u64; 1] = [trunc]
  ## 1/2. an element read IS the callee — no intermediate binding.
  r1 := fs[0](9)
  r2 := fs[1](5)
  ## 3. a RUNTIME index: add1(3) + dbl(3) = 4 + 6 = 10.
  mut r3 : u64 = 0
  mut i : u64 = 0
  while i < 2 {
    r3 = r3 + fs[i](3)
    i = i + 1
  }
  ## 4. the same element, parenthesized — the parentheses carry no meaning once the group closes.
  r4 := (fs[0])(9)
  ## 5. a parenthesized bare NAME is just that name: `(add1)(9)` IS `add1(9)`.
  r5 := (add1)(9)
  ## 6. through a struct FIELD holding the array, at a RUNTIME index. add1(3) + dbl(3) = 10.
  t := Tbl(fs = [add1, dbl])
  mut r6 : u64 = 0
  mut j : u64 = 0
  while j < 2 {
    r6 = r6 + t.fs[j](3)
    j = j + 1
  }
  ## 7. two parameters — the SysV argument registers, with the code pointer kept off them.
  r7 := ops[0](4, 6)
  ## 8. the call is itself an ARGUMENT of another call. 14 - 4 = 10.
  r8 := id(ops[1](14, 4))
  ## 9. and NESTED in its own argument list. (7 - 4) + 7 = 10.
  r9 := ops[0](ops[1](7, 4), 7)
  ## 10. a FLOAT parameter rides %xmm — the class comes from the recovered fn type.
  r10 := gs[0](10.5)
  return r1 + r2 + r3 + r4 + r5 + r6 + r7 + r8 + r9 + r10
}
