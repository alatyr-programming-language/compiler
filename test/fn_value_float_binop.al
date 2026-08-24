## e2e (FN-6 / the SysV FLOAT ABI — an INDIRECT call whose `f64` result flows through a FLOAT BINOP).
## The ANCHOR half of the `fn_value_float_ret.al` regression: this shape was accidentally CORRECT
## before the return class existed (the callee left the result in %xmm0 and the surrounding `+` read
## %xmm0 again), so it pins that adding the class did not perturb it — the value must stay right.
##
## It also covers the ARGUMENT class, the second half of the same defect: a float argument to a fn
## value rode a GENERAL register while the callee (a real fn with a real `f64` parameter) read %xmm.
## That was right only when %xmm0 happened to still hold the argument — true for `h(0.5)` (a literal
## loads through %xmm0) but NOT for `h(v)`, a read out of a frame slot, which silently passed the
## stale %xmm0 instead. 21.0 + 1.0 = 22.
dblf := fn(x : f64) -> f64 { return x * 2.0 }

main := fn() -> u64 {
  h := dblf
  v : f64 = 10.5
  mut s : f64 = 0.0
  s = s + h(v)        ## a NON-literal float argument (a frame-slot read) + a float-binop consumer
  s = s + h(0.5)      ## a float LITERAL argument — the shape that was accidentally right
  return u64(s)
}
