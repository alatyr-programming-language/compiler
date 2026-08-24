Rec := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut arr : [Rec; 2]
  arr[0].a = 42
  return arr
}
