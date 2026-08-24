## DEFER (§9.3): a `defer` in a `loop` BODY runs on `break`. Each iteration registers bump(1); on the
## break iteration the loop's body-frame defers drain before the jump. Accumulating ACC (base 10):
## iterations 1 and 2 fall through (i < 3) → bump(1) at each end → ACC 1, 11; iteration 3 `break`s →
## its defer bumps too → ACC 111. If the break-path defer were dropped, ACC would be 11; if it ran at
## the function end instead, ACC would be 11 then a late bump (1121 or similar).
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }
f := fn() -> u64 {
  mut i : u64 = 0
  loop {
    defer bump(1)
    i = i + 1
    if i >= 3 { break }
  }
  return ACC
}
main := fn() -> u64 { return f() }