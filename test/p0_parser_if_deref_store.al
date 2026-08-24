## P0 parser: a terminal statement-if must keep whole-value deref stores in both arms.
## The pointer argument is the place mutated by the store; main exercises both the
## true arm (8) and false arm (9) through the public call path.
set := fn(dp : ptr(mut u64), k : u64) {
  if k == 5 {
    deref(dp) = 8
  } else {
    deref(dp) = 9
  }
}

main := fn() -> u64 {
  mut yes : u64 = 0
  mut no : u64 = 0
  set(ptr(mut yes), 5)
  set(ptr(mut no), 6)
  if yes != 8 { return 1 }
  if no != 9 { return 2 }
  return 42
}
