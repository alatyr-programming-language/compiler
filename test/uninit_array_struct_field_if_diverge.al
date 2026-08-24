Rec := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut arr : [Rec; 2]
  if false { return 1 } else { arr[0].a = 41 }
  return arr[0].a + 1
}
