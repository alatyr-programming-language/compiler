## Leak-detection (spec §10 / D86): an @owning handle created in a straight-line fn and then NEVER used
## (not discharged, returned, or passed) is a LEAK — check must reject (rc 1). `Owned` is @owning; `h`
## is bound from a ctor and then dropped on the floor.
Owned := @owning struct { v : u64 }
mk := fn() -> Owned { Owned(v = 5) }
main := fn() -> u64 {
  h := mk()
  0
}
