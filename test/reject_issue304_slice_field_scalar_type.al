## Issue #304 — a declared Slice(u64) field must enforce its element type at a store.
H := struct { values : Slice(u64) }

main := fn() -> u64 {
  mut values := [10, 20, 30]
  mut h := H(values = values[0..3])
  h.values[1] = "text"
  0
}
