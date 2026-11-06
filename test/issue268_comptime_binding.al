E := enum { Zero, One }
comptime base : u64 = 5
comptime inferred := base + 2

main := fn() -> u64 {
  comptime local : u64 = inferred + 1
  comptime flag := true
  comptime v : u64 = 5
  comptime which : E = E.One
  comptime if flag {
    comptime if v == 5 { return local + 34 } else { return 7 }
  } else { return 0 }
  if which == E.One { return local + 0 }
  return 0
}
