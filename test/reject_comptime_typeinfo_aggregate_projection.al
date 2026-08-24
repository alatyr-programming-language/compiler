## The bounded projection slice is scalar ordinary struct fields only. An aggregate field remains
## fail-loud until its copy/value ABI is unified; accepting this as a scalar would be a miscompile.
C := struct { x : u64 }
S := struct { c : C, y : u64 }

main := fn() -> u64 {
  v := S(c = C(x = 40), y = 2)
  mut total : u64 = 0
  comptime for f in typeinfo(S).fields { total = total + v.(f) }
  total
}
