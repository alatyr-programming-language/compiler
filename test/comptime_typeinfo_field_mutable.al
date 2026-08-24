## CT-6: Field.mutable reflects the source-level mut marker during a field derive.
S := struct { mut x : u64, y : u64 }

count_mut := fn(T : type) -> u64 {
  mut n : u64 = 0
  comptime for f in typeinfo(T).fields {
    if f.mutable { n = n + 1 }
  }
  n
}

main := fn() -> u64 { count_mut(S) + 41 }
