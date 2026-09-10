## Issue #304 — a declared Slice(bool) field must enforce its element type at a store.
H := struct { flags : Slice(bool) }

main := fn() -> u64 {
  mut flags := [false, false]
  mut h := H(flags = flags[0..2])
  h.flags[0] = "text"
  0
}
