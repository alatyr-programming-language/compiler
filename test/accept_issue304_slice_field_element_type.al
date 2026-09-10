## Issue #304 controls — declared scalar slice fields retain valid element stores.
H := struct { values : Slice(u64), flags : Slice(bool) }

main := fn() -> u64 {
  mut values := [10, 20, 30]
  mut flags := [false, false]
  mut h := H(values = values[0..3], flags = flags[0..2])
  h.values[1] = 40
  h.flags[0] = true
  if not h.flags[0] { return 1 }
  h.values[1] + 2
}
