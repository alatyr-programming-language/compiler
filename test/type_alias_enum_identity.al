## One-hop type alias keeps the enum constructor nominally attached to Color.
Color := enum { Red, Green }
C := Color

main := fn() -> u64 {
  c := C.Green
  match c {
    Red => { return 1 }
    Green => { return 42 }
  }
}
