## e2e (FN-6 — the STRUCT return classes of an INDIRECT call). Companion to `fn_value_enum_ret`: the
## same missing return class, on the two STRUCT conventions.
##   * 1..7 words — the REGISTER return (word k in %rax/%rdx/%rcx/…). The indirect call kept only
##     `pushq %rax` and the destination local was never bound as a struct, so every field read 0.
##   * >= 8 words — SRET: the caller must hand the destination's address down as the hidden %rdi.
##     Unclassified, the indirect call left the FIRST USER ARGUMENT in %rdi and the callee wrote the
##     whole struct through it — a SEGFAULT (exit 139), not a wrong value.
## Both classes are now recovered from the fn value's declared/bound signature, so the destination is
## bound + received exactly as for the direct call the value forwards to.
## (2 + 3) + (4 + 4 + 7) + (7 + 15) = 5 + 15 + 22 = 42.
P := struct { x : u64, y : u64 }
S := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64 }
W := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }

mkp := fn(v : u64) -> P { return P(x = v, y = v + 1) }
mks := fn(v : u64) -> S { return S(a = v, b = 1, c = 2, d = 3, e = 4, f = 5, g = v + 3) }
mkw := fn(v : u64) -> W { return W(a = v, b = 1, c = 2, d = 3, e = 4, f = 5, g = 6, h = 7, i = v + 8) }

## the WIDE (sret) case reached through a fn-value PARAMETER — the hidden result pointer must be wired
## the same way when the code pointer arrives as an argument
wide_via_param := fn(fv : fn(u64) -> W, v : u64) -> u64 {
  w := fv(v)
  return w.a + w.i
}

main := fn() -> u64 {
  ## 2-word struct — the register return (%rax/%rdx)
  fp := mkp
  p := fp(2)
  ## 7-word struct — the widest register return (%rax..%r11)
  fs : fn(u64) -> S = mks
  s := fs(4)
  ## 9-word struct — SRET through the hidden result pointer
  w := wide_via_param(mkw, 7)
  return (p.x + p.y) + (s.a + s.e + s.g) + w
}
