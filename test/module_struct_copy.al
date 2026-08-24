## e2e — COPY a module-level const struct into a mutable local (`mut p := ORIGIN`). The const RHS is
## resolved to its StructLit, so the binding sizes `p` as the struct and copies the const's field
## values into `p`'s slots (via the existing struct-lit machinery). `p` is then an independent local:
## mutating `p.x` doesn't touch the const. Returns 42 = 40 (assigned) + 2 (copied from ORIGIN.y).
Pt := struct { x : u64, y : u64 }
ORIGIN := Pt(x = 1, y = 2)
main := fn() -> u64 {
  mut p := ORIGIN
  p.x = 40
  p.x + p.y
}
