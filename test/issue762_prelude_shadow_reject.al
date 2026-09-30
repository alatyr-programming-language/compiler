## e2e / issue #762 — the other direction: the program's OWN `Arena` is the declaration a literal is
## checked against, so a value that fits only the prelude's `alloc::Arena` is refused.
##
## The shipped arena's first field is a pointer, and the implicit `usize ↔ ptr(T)` seam (#529) accepted
## an integer there. Checked against the shipped declaration, `Arena(live = 5)` therefore passed; checked
## against the declaration below — the one Modules §3 resolves the bare name to — an integer is not a
## `bool`, and the literal is a located type mismatch.
Arena := struct { live : bool }

main := fn() -> u64 {
  a := Arena(live = 5)
  return 0
}
