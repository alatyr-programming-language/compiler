## e2e (build_reject_has) — an enum-valued comptime binding remains outside the bounded scalar fold.
E := enum { Zero, One }


main := fn() -> u64 {
  mut x : u64 = 5
  comptime v : E = E.One
  comptime if v == E.One { x = 30 } else { x = 70 }
  return x
}
