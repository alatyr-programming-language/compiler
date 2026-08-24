## CT-6: a range bound must use the type named by its own typeinfo(X) argument,
## not the enclosing generic instance type.
B := struct { p : u64, q : u64, r : u64, s : u64 }
C := enum { X, Y, Z, W }

count_b := fn(T : type, value : T) -> u64 {
  mut total : u64 = 0
  comptime for i in 0 .. typeinfo(B).n { total = total + i }
  comptime for i in 0 .. typeinfo(B).fields.len { total = total + i }
  comptime for i in 0 .. typeinfo(C).variants.len { total = total + i }
  total
}

main := fn() -> u64 { count_b(u64, 1) + 24 }
