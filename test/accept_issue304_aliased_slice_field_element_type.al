## Issue #304 controls — valid stores survive one-hop aliases of scalar Slice(T) fields.
Numbers := Slice(u64)
Flags := Slice(bool)
H := struct { values : Numbers, flags : Flags }

main := fn() -> u64 {
  ## Keep backend execution under #621 while sema checks both aliased store classes.
  if false {
    mut values := [10, 20]
    mut flags := [false, false]
    mut h := H(values = values[0..2], flags = flags[0..2])
    h.values[0] = 42
    h.flags[1] = true
  }
  42
}
