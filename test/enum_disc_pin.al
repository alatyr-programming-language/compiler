## spec Types §6.2 — an enum variant MAY PIN its discriminant with `= N`. This OBSERVES the exact pinned
## tag as stored (FFI/serialization observability): it takes the address of the enum local and reads
## word 0 (the tag). Before the fix, `A = 5` / `B = 10` were parsed as bogus extra variants and the tag
## was assigned POSITIONALLY (A=0, B=1) — a silent miscompile. Correct: A reads 5, B reads 10 → 42.
Code := enum { A = 5, B = 10 }

main := fn() -> u64 {
  mut a := Code.A
  ta := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(a))))
  mut b := Code.B
  tb := unchecked deref(unchecked bitcast(ptr(mut u64), unchecked bitcast(usize, ptr(b))))
  mut acc := 0
  if ta == 5 { acc = acc + 20 }
  if tb == 10 { acc = acc + 22 }
  acc
}
