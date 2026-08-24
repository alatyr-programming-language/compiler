## e2e — `for e in ARR` over a mutable STRUCT-array global. The array is laid out in `.data` as N*stride
## field cells (each struct's fields ascending), the loop var is bound as the element struct, and each
## iteration copies `stride` words from `LABEL + i*stride*8` into it. Sums x+y over 3 Pts:
## (10+1)+(20+2)+(8+1) = 42.
Pt := struct { x : u64, y : u64 }
mut ARR := [Pt(x = 10, y = 1), Pt(x = 20, y = 2), Pt(x = 8, y = 1)]
main := fn() -> u64 {
  mut acc := 0
  for e in ARR { acc = acc + e.x + e.y }
  acc
}
