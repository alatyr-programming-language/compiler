## Issue #304 — a one-hop alias of Slice(u64) must retain its field element type.
Numbers := Slice(u64)
H := struct { values : Numbers }

main := fn() -> u64 {
  mut values := [10, 20]
  mut h := H(values = values[0..2])
  h.values[0] = "text"
  0
}
