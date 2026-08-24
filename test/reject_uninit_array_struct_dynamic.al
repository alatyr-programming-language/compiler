Rec := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut arr : [Rec; 2]
  mut i := 0
  arr[i].a = 42
  return arr[i].a
}
