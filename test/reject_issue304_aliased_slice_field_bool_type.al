## Issue #304 — a one-hop alias of Slice(bool) must retain its field element type.
Flags := Slice(bool)
H := struct { flags : Flags }

main := fn() -> u64 {
  mut flags := [false, false]
  mut h := H(flags = flags[0..2])
  h.flags[1] = "text"
  0
}
