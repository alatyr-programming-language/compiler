## Raw union (spec Types §6.3) — DEFINED BIT REINTERPRETATION + NO TAG WORD (untagged, §4.4 / I11).
## Write member `s` (i64 -1 = all bits set), then read a DIFFERENT member `u` (u64): the offset-0 bytes
## are reinterpreted, yielding u64::MAX. This is defined (hardware-defined reinterpret), never UB.
## It also PROVES the union carries no discriminant: were there a tag word at offset 0 (as an enum has),
## reading `u` would return the tag (0), not the reinterpreted -1 bits.
U := union { s(i64), u(u64) }
main := fn() -> u64 {
  x := U.s(0 - 1)
  v := unchecked (x.u)
  if v == 18446744073709551615 { return 42 }
  return 7
}
