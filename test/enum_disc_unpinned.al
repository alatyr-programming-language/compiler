## spec Types §6.2 REGRESSION — an UN-PINNED enum is unchanged: discriminants stay positional
## (0,1,2,…), exactly the former behaviour (the neutrality proof — this is what keeps the fixpoint
## byte-identical). Green reads 1, Blue reads 2 → 42.
Col := enum { Red, Green, Blue }

main := fn() -> u64 {
  mut g := Col.Green
  tg := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(g))))
  mut b := Col.Blue
  tb := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(b))))
  mut acc := 0
  if tg == 1 { acc = acc + 20 }
  if tb == 2 { acc = acc + 22 }
  acc
}
