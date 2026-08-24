## Backend range fold: a direct typeinfo(B) bound has no enclosing generic instance to fall back to.
B := struct { p : u64, q : u64, r : u64, s : u64 }

main := fn() -> u64 {
  mut total : u64 = 0
  comptime for i in 0 .. typeinfo(B).n { total = total + i }
  total + 36
}
