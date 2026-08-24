## P1 aggregate-array equality — nested plain structs whose leaves are native scalar words.
## The local path and the concrete by-reference `[Cell; 3]` parameter path must compare the
## complete word-granular layout, including the nested Leaf's second word.
Leaf := struct { x : u64, y : u64 }
Cell := struct { pad : u64, inner : Leaf, z : u64 }

compare_params := fn(xs : [Cell; 3], ys : [Cell; 3]) -> u64 {
  mut i := 0
  mut j := 1
  mut acc : u64 = 0
  if xs[i] != ys[j] { acc = acc + 1 }
  if xs[2] == ys[2] { acc = acc + 2 }
  if xs[0] == ys[0] { acc = acc + 4 }
  if xs[1] == ys[1] { acc = acc + 8 }
  if xs[1] != ys[2] { acc = acc + 20 }
  acc
}

main := fn() -> u64 {
  a : [Cell; 3] = [
    Cell(pad = 1, inner = Leaf(x = 10, y = 20), z = 3),
    Cell(pad = 1, inner = Leaf(x = 10, y = 21), z = 3),
    Cell(pad = 1, inner = Leaf(x = 10, y = 20), z = 3)
  ]
  b : [Cell; 3] = [
    Cell(pad = 1, inner = Leaf(x = 10, y = 20), z = 3),
    Cell(pad = 1, inner = Leaf(x = 10, y = 21), z = 3),
    Cell(pad = 1, inner = Leaf(x = 10, y = 20), z = 3)
  ]
  mut i := 0
  mut j := 1
  mut acc : u64 = 0
  if a[i] != a[j] { acc = acc + 1 }
  if a[0] == a[2] { acc = acc + 2 }
  if a[0] == b[0] { acc = acc + 4 }
  acc + compare_params(a, b)
}
