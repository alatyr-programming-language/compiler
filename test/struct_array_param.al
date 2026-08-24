## A struct-element array PARAM `a : [P; N]` indexed + field-accessed IN BOUNDS. Regression guard for a
## latent bug: a struct/enum array param whose element type NAME is 1 character (here `P`) had its slot's
## `snl` = len("P") = 1, colliding with the runtime-len SLICE marker (`snl == 1`) → the slice bounds
## check read the wrong frame slot as a "length" and trapped even an in-bounds index. Gating the slice
## check on a scalar element (`eek == 0`) fixed it. `a[0].x = 42`.
P := struct { x : u64, y : u64 }
g := fn(a : [P; 2], i : u64) -> u64 { return a[i].x }
main := fn() -> u64 {
  arr := [P(x = 42, y = 0), P(x = 1, y = 1)]
  return g(arr, 0)
}
