## e2e — an EXPLICIT `return` of a WIDE enum ({disc, payload…} > 7 words) must take the SRET path
## (write the whole value through the hidden result pointer), not the two-register convention.
## `emit_return_value` (the trailing-value / tail-`match`-arm path) already checked `ret_sret` before
## `ret_enum`; the `Stmt::Return` path did NOT, so an explicit `return` of a wide enum fell to
## `emit_enum_value` — which tops out at %r11 (7 words). That gave a SILENT 0 payload for the
## `return e` (enum Var) form and a fail-loud panic for the `return E.V(…)` (EnumLit) form.
##
## `W` is disc + 7 payload = 8 words (the first width past the budget); `R` is disc + 6 = 7 words —
## the register-return BOUNDARY, which must stay on the unchanged register path. Returns
## (1+7) + (20+5) + (1+2) = 36.
W := enum { Big(u64, u64, u64, u64, u64, u64, u64), Small(u64) }
R := enum { Six(u64, u64, u64, u64, u64, u64), None }

mkvar := fn() -> W {
  e := W.Big(1, 2, 3, 4, 5, 6, 7)
  return e                                  ## wide enum, Var form — was a silent 0
}
mklit := fn() -> W { return W.Big(20, 0, 0, 0, 0, 0, 5) }   ## wide enum, EnumLit form — was fail-loud
mkreg := fn() -> R {
  r := R.Six(1, 0, 0, 0, 0, 2)
  return r                                  ## 7 words — the register-return boundary, unchanged
}

main := fn() -> u64 {
  v := mkvar()
  w := mklit()
  z := mkreg()
  s := match v { W::Big(a, b, c, d, e, f, g) => a + g, W::Small(x) => 0 }   ## 8
  t := match w { W::Big(a, b, c, d, e, f, g) => a + g, W::Small(x) => 0 }   ## 25
  u := match z { R::Six(a, b, c, d, e, f) => a + f, R::None => 0 }          ## 3
  s + t + u                                                                  ## 36
}
