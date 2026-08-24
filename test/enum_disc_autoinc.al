## spec Types §6.2 — after a pinned variant, following UNASSIGNED variants continue from `N + 1`
## (first variant `0`). `{A=5, B, C=20, D}` → A=5, B=6, C=20, D=21. This reads B's and D's stored tag
## words: B == 6 (auto-inc after the A=5 pin) and D == 21 (auto-inc after the C=20 pin) → 42.
E := enum { A = 5, B, C = 20, D }

main := fn() -> u64 {
  mut b := E.B
  tb := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(b))))
  mut d := E.D
  td := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(d))))
  mut acc := 0
  if tb == 6 { acc = acc + 21 }
  if td == 21 { acc = acc + 21 }
  acc
}
