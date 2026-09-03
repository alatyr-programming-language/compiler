## #410 — the ONE-ACCESS verification mode `unchecked a[i]` must scope the ACCESS, not the BASE.
## Types §6.4: element access is `base + i × stride`, bounds-checked by default, and "inside an
## `unchecked` scope the bounds check is omitted (CG-7/CG-6 — `unchecked a[i]` for one access,
## `unchecked { … }` for a region)". Only the CHECK may be dropped; the address computation may not.
##
## The parser took the modifier's operand at the PRIMARY level, so `unchecked a[i]` parsed as
## `(unchecked a)[i]`. The index base was then a nameless `Unchecked` node that no `Index` recogniser
## in lower matches, it fell through to the untyped tail of `emit_index_addr`, and that resolves a
## nameless base to frame SLOT 0 — a clean compile reading unrelated memory, on the most ordinary
## shape in the language. Measured on the parent, each row below read slot 0 and returned its own
## failure code; the corresponding CHECKED read was right in every case:
##
##   fixed-array local, elem 1   `unchecked xs[1]`   →  0  (want 42)   ## rc 101
##   fixed-array local, elem 0   `unchecked xs[0]`   →  0  (want 71)   ## rc 102
##   typed slice                 `unchecked v[1]`    →  0  (want 93)   ## rc 103
##   the same, minus a constant  `unchecked xs[2]-51`→ 210 (want 42)   ## rc 105
##
## This fixture stays inside the SCALAR array/slice kernel, so all four backends run it: on the parent
## AArch64, RISC-V64 and WAT all trapped (133/133/134 — never a second wrong value), and with the fix
## all four reach 42. The `str`-base spellings of the same defect are in
## `test/unchecked_index_binds_access_str.al`, which the non-x86 backends still trap on.
##
## The neighbours are deliberately non-zero and pairwise distinct (71, 42, 93), so a slot-0 read
## cannot pass for a plausible element, and each check owns a distinct failure code from 100 rather
## than being folded into one arithmetic total (#386). The `unchecked { … }` REGION form was already
## correct and is kept here so a fix cannot trade one form for the other.
main := fn() -> u64 {
  ## a fixed-array local base — the shape a hot loop writes, and the reason `unchecked` exists.
  xs : [u64; 3] = [71, 42, 93]
  if unchecked xs[1] != 42 { return 101 }
  ## element 0 is non-zero, so reading the frame's slot 0 stays distinguishable from reading xs[0].
  if unchecked xs[0] != 71 { return 102 }
  ## a typed slice base — `xs[1..3]` is the view {42, 93}, so element 1 is 93.
  v := xs[1..3]
  if unchecked v[1] != 93 { return 103 }
  ## the REGION form, which was already correct: it must stay correct.
  r := unchecked { xs[1] }
  if r != 42 { return 104 }
  ## the modifier still binds LOOSER than every binary operator, so this is `(unchecked xs[2]) - 51`
  ## and not `unchecked (xs[2] - 51)` — the operand ends at the access, exactly as it did before.
  if unchecked xs[2] - 51 != 42 { return 105 }
  return 42
}
