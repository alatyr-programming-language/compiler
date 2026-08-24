Rec := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut arr : [Rec; 2]
  if true { arr[0].a = 20 } else { arr[0].a = 22 }
  return arr[0].a * 2
}
