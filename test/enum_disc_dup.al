## spec Types §6.2 — "Two variants resolving to the same value are ill-formed." Two variants pinned to
## the SAME discriminant (5) MUST be rejected LOUD at build (a compile diagnostic), never silently
## emitted with an ambiguous tag. `build_reject` asserts a non-zero build rc.
Bad := enum { A = 5, B = 5 }

main := fn() -> u64 {
  x := Bad.A
  match x {
    Bad.A => { 0 }
    Bad.B => { 1 }
  }
}
