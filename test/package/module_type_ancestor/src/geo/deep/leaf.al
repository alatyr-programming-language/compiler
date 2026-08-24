## A grandchild: the same bare names resolved TWO steps up.
pub run := fn() -> u64 {
  if Box.size() != 8 { return 6 }
  if size(E) != 16 { return 7 }
  if size(Cell(Box)) != 16 { return 8 }
  return Box.size() + size(E) - 7
}
