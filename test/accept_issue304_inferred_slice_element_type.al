## Issue #304 controls — inferred slices retain valid scalar and nominal element stores.
P := struct { x : u64 }

main := fn() -> u64 {
  ## Keep backend write execution under #213 while sema checks all three store classes here.
  if false {
    mut ints : [u64; 2] = [1, 2]
    mut flags : [bool; 1] = [false]
    mut points : [P; 1] = [P(x = 1)]
    si := ints[0..2]
    sb := flags[0..1]
    sp := points[0..1]
    si[0] = 40
    sb[0] = true
    sp[0] = P(x = 42)
  }
  42
}
