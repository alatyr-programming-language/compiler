## e2e / issues #913 and #912 — a struct literal with a struct-typed field, delivered by value.
##
## A struct literal returned in registers, or carried as an enum payload, was lowered one pushed word
## per FIELD. A field of struct type is not one pushed word: a one-word nested struct (`W { k : K }`,
## `K { ty : i64 }`) pushed the `$0` placeholder, so `w.k.ty` read 0 (#913); a wider one read past
## the field list and crashed the compiler (#912). The literal is now built whole and its words
## delivered.
##
## 42 means every value held. Each miss owns its own code from 100 up.
K := struct { ty : i64 }
K2 := struct { ty : i64, sg : i64 }
W := struct { k : K }
WL := struct { k : K, l : i64 }
W2 := struct { k : K2 }
E := enum { A(i64), B }
WE := struct { e : E, l : i64 }
R := enum { Ok(W), Bad }

opt_w := fn() -> Option(W) { Option(W).Some(W(k = K(ty = 7))) }
opt_wl := fn() -> Option(WL) { Option(WL).Some(WL(k = K(ty = 5), l = 3)) }
opt_w2 := fn(b : bool) -> Option(W2) {
  if b { return Option(W2).Some(W2(k = K2(ty = 4, sg = 6))) }
  Option(W2).None
}
opt_we := fn() -> Option(WE) { Option(WE).Some(WE(e = E.A(9), l = 2)) }
res_w := fn() -> R { R.Ok(W(k = K(ty = 11))) }
plain_w := fn() -> W { W(k = K(ty = 13)) }
plain_wl := fn() -> WL { WL(k = K(ty = 1), l = 2) }

main := fn() -> u64 {
  mut t : i64 = 0
  match opt_w() { Some(w) => { if w.k.ty != 7 { return 100 }; t = t + w.k.ty }; None => { return 101 } }
  o := opt_wl()
  match o { Some(w) => { if w.k.ty != 5 or w.l != 3 { return 102 }; t = t + w.k.ty + w.l }; None => { return 103 } }
  match opt_w2(true) { Some(w) => { if w.k.ty != 4 or w.k.sg != 6 { return 104 } }; None => { return 105 } }
  match opt_w2(false) { Some(w) => { return 106 }; None => {} }
  match opt_we() {
    Some(w) => { match w.e { A(x) => { if x != 9 or w.l != 2 { return 107 } }; B => { return 108 } } }
    None => { return 109 }
  }
  match res_w() { Ok(w) => { if w.k.ty != 11 { return 110 } }; Bad => { return 111 } }
  p := plain_w()
  if p.k.ty != 13 { return 112 }
  q := plain_wl()
  if q.k.ty != 1 or q.l != 2 { return 113 }
  ## 7 + (5 + 3) = 15; 15 + 27 = 42
  u64(t + 27)
}
