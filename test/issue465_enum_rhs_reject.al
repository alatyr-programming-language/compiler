## issue #465 — the RESIDUAL of the same defect, and why it is a REJECT rather than a fixture that
## runs. `emit_enum_assign`'s wildcard used to emit NO INSTRUCTION for every right-hand side it did
## not recognise while its caller reported the store as done, so the destination kept its previous
## words and the program answered stale with exit status 0.
##
## `emit_enum_place_words_at` now REPORTS whether it wrote anything, and the wildcard turns a `false`
## into a located diagnostic. A mutable-GLOBAL enum source is one shape it still has no addressing
## for: the global has no frame slot, so neither the place walk nor the return registers describe it.
## AGENTS.md is explicit that this is the acceptable outcome — a trap is acceptable, a wrong value is
## not — and it is strictly better than the silent stale field this same program produced on the
## parent, where it compiled cleanly and answered 1.
##
## Asserted with `build_reject_has` rather than a bare `build_reject`, so a fail-loud accident
## somewhere else cannot satisfy the row. The searched needle is deliberately NOT quoted anywhere in
## this file: the `*_has` helpers grep the whole artifact, and a header that quotes its own assertion
## passes on an unfixed compiler.

Tag := enum { Red, Green, Blue }
Holder := struct { t : Tag, n : u64 }

mut G := Tag.Green

main := fn() -> u64 {
  mut h := Holder(t = Tag.Red, n = 7)
  h.t = G
  if h.t == Tag.Green { 42 } else { 1 }
}
