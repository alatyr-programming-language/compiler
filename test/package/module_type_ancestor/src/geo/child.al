## A direct child: every type name below is BARE and resolved ONE step up the ancestor chain.
## 8 (Box) + 8 (U) + 16 (E) + 8 (Handle) + 16 (Cell(Box)) is not summed directly — each is checked
## against the ANCESTOR's value so a wrong resolution is a distinct wrong return, not a coincidence.
pub run := fn() -> u64 {
  if Box.size() != 8 { return 1 }
  if size(U) != 8 { return 2 }
  if size(E) != 16 { return 3 }
  if Handle.size() != 8 { return 4 }
  if size(Cell(Box)) != 16 { return 5 }
  ## a struct LITERAL: the field-name set is the ancestor's, so `a` is a field and `d` is not.
  v := Box(a = 20)
  ## the @require contract: `geo`s predicate accepts 5, the decoys' rejects it (a trap, not a value).
  z := Nz(5)
  return v.a + u64(z)
}
