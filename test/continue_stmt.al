## e2e (the `continue` statement — skip to the next iteration of the nearest enclosing loop).
## `continue` was parsed as a bare identifier (unsurfaced by the port) → a silent no-op that
## corrupted loop bodies. Now it is a real `Stmt.Continue` that jumps to the loop's CONTINUE target
## (`LCtx.cont`): a `while`'s guard, a `loop`'s top, a `for`'s increment label (so the index still
## advances). Exercises `continue` in a `while`, a range-`for`, an infinite `loop` (with `break`),
## and an iterable-`for` over an array — plus a NESTED loop (inner `continue` re-iterates the inner
## loop only, not the outer).
main := fn() -> u64 {
  ## while: skip i==5 -> 1+2+3+4+6+7+8+9+10 = 50
  mut i : u64 = 0
  mut w : u64 = 0
  while i < 10 { i = i + 1; if i == 5 { continue } w = w + i }
  ## range-for: skip odds in 0..10 -> 0+2+4+6+8 = 20
  mut f : u64 = 0
  for k in 0..10 { if k % 2 == 1 { continue } f = f + k }
  ## loop: sum 1..9, break past 100 -> 45
  mut j : u64 = 0
  mut lp : u64 = 0
  loop { j = j + 1; if j > 100 { break } if j > 9 { continue } lp = lp + j }
  ## iterable-for over an array: skip the 99 sentinels -> 10+20+12 = 42
  a : [u64; 6] = [10, 99, 20, 99, 12, 99]
  mut ar : u64 = 0
  for x in a { if x == 99 { continue } ar = ar + x }
  ## nested: inner continue skips inner odd; outer runs 3 times -> inner sum(0,2,4)=6 each *3 = 18
  mut nn : u64 = 0
  for p in 0..3 { for q in 0..5 { if q % 2 == 1 { continue } nn = nn + q } }
  ## w=50, f=20, lp=45, ar=42, nn=18 -> 42 + (w-50) + (f-20) + (lp-45) + (ar-42) + (nn-18) = 42
  42 + (w - 50) + (f - 20) + (lp - 45) + (ar - 42) + (nn - 18)
}
