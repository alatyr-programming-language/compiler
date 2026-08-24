## e2e — `for e in <literal-bound struct array>`. A literal binding `arr := [Pt(…), …]` has no
## `[T; N]` annotation, so the element count was lost and the loop ran ZERO times (silent empty loop).
## The count is now recovered from the reserved element filler slots. Sums x+y over 3 Pts:
## (10+1) + (20+2) + (8+1) = 42.
Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  arr := [Pt(x = 10, y = 1), Pt(x = 20, y = 2), Pt(x = 8, y = 1)]
  mut acc := 0
  for e in arr {
    acc = acc + e.x + e.y
  }
  acc
}
