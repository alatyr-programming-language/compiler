## three overloads sharing the first parameter type. Resolution by the complete
## signature picks `h(u64, A)` / `h(u64, B)` for the struct arguments and `h(u64, u64)` for the
## all-integer call — a bare integer literal binds only to an integer scalar parameter, never a
## struct one, so `h(2, 10)` is not an ambiguous wildcard.
A := struct { v : u64 }
B := struct { v : u64 }
h := fn(x : u64, a : A) -> u64 { return 10 }
h := fn(x : u64, b : B) -> u64 { return 20 }
h := fn(x : u64, y : u64) -> u64 { return x + y }
main := fn() -> u64 {
  a := A(v = 1)
  b := B(v = 2)
  return h(1, a) + h(1, b) + h(2, 10)
}
