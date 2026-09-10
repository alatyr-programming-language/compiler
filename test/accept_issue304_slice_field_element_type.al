## Issue #304 controls — declared scalar slice fields retain valid element stores.
H := struct { values : Slice(u64), flags : Slice(bool) }

main := fn() -> u64 {
  ## Keep backend write execution under #621 while sema checks both store classes here.
  if false {
    mut values := [10, 20, 30]
    mut flags := [false, false]
    mut h := H(values = values[0..3], flags = flags[0..2])
    h.values[1] = 40
    h.flags[0] = true
  }
  42
}
