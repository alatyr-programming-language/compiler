## §6.2 / Grammar §2.4 — enum discriminant pins use the same integer-literal grammar as
## every other literal: binary, octal, hexadecimal, and `_` separators must all retain
## their full value. The raw tag reads make a partial/manual decoder observable.
Code := enum { A = 0b1_010, B = 0o1_013, C = 0x2_10 }

main := fn() -> u64 {
  mut a := Code.A
  ta := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(a))))
  mut b := Code.B
  tb := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(b))))
  mut c := Code.C
  tc := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(c))))
  mut acc := 0
  if ta == 10 { acc = acc + 14 }
  if tb == 523 { acc = acc + 14 }
  if tc == 528 { acc = acc + 14 }
  acc
}
