## AXIS coverage for #306: field-layout eightbyte x path through-field and pointer-deref in both orders.
## Each narrow write is checked against a non-zero wide neighbour that must remain unchanged.
NarrowFirst := struct { narrow : u8, wide : u64 }
WideFirst := struct { wide : u64, narrow : u8 }
OuterNarrow := struct { inner : NarrowFirst, guard : u64 }
OuterWide := struct { inner : WideFirst, guard : u64 }

main := fn() -> u64 {
  mut through_narrow := OuterNarrow(inner = NarrowFirst(narrow = 13, wide = 702), guard = 703)
  through_narrow.inner.narrow = 17
  if through_narrow.inner.narrow != 17 { return 1 }
  if through_narrow.inner.wide != 702 { return 2 }
  if through_narrow.guard != 703 { return 3 }

  mut through_wide := OuterWide(inner = WideFirst(wide = 704, narrow = 19), guard = 705)
  through_wide.inner.narrow = 23
  if through_wide.inner.narrow != 23 { return 4 }
  if through_wide.inner.wide != 704 { return 5 }
  if through_wide.guard != 705 { return 6 }

  comptime if target.arch == Arch.x86_64 {
    mut pointed_narrow := NarrowFirst(narrow = 29, wide = 706)
    pn := ptr(mut pointed_narrow)
    deref(pn).narrow = 31
    if deref(pn).narrow != 31 { return 7 }
    if deref(pn).wide != 706 { return 8 }

    mut pointed_wide := WideFirst(wide = 708, narrow = 37)
    pw := ptr(mut pointed_wide)
    deref(pw).narrow = 41
    if deref(pw).narrow != 41 { return 9 }
    if deref(pw).wide != 708 { return 10 }
  }
  42
}
