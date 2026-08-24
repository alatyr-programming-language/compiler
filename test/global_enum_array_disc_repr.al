## e2e — the `.data` image of an ENUM-element ARRAY GLOBAL uses the variant's real DISCRIMINANT, not
## its positional index: `C` PINS its variants (Types §6.2 `= N`), so a positional image would tag
## `C.B(…)` as 1 where the dispatch expects 9. And a `@repr(u8)`-tagged enum (§8) still images its tag
## as a full `.quad` cell — the element is word-addressed, and the narrow tag load reads the low byte
## of that word (little-endian), so the image and the `match` agree. 2 + 40 = 42.
C := enum { A(u64) = 5, B(u64) = 9 }

@repr(u8)
R := enum { N, A(u64), B(u64) }

mut GC := [C.A(1), C.B(2)]
mut GR := [R.B(7), R.N, R.A(3)]

main := fn() -> u64 {
  mut acc : u64 = 0
  ## the PINNED-discriminant array: element 1 must dispatch to `B` (disc 9), not to arm index 1.
  match GC[1] {
    C::A(n) => { return 1 }
    C::B(n) => { acc = acc + n }
  }
  match GC[0] {
    C::A(n) => { if n != 1 { return 2 } }
    C::B(n) => { return 3 }
  }
  ## the `@repr(u8)` array: read every element, then WRITE over the nullary one and read it back.
  match GR[0] { R::N => { return 4 } R::A(n) => { return 5 } R::B(n) => { if n != 7 { return 6 } } }
  match GR[1] { R::N => {} R::A(n) => { return 7 } R::B(n) => { return 8 } }
  match GR[2] { R::N => { return 9 } R::A(n) => { if n != 3 { return 10 } } R::B(n) => { return 11 } }
  GR[1] = R.A(40)
  match GR[1] {
    R::N => { return 12 }
    R::A(n) => { acc = acc + n }
    R::B(n) => { return 13 }
  }
  ## the neighbours survived the strided write.
  match GR[0] { R::N => { return 14 } R::A(n) => { return 15 } R::B(n) => { if n != 7 { return 16 } } }
  match GR[2] { R::N => { return 17 } R::A(n) => { if n != 3 { return 18 } } R::B(n) => { return 19 } }
  acc                                    ## 2 + 40 = 42
}
