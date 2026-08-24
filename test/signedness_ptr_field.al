## Direct `deref(Var).field` signedness: the declared field type selects each operation.
Rec := struct { u : u64, s : i64 }

check_u := fn(p : ptr(mut Rec)) -> u64 {
  if deref(p).u < 1 { return 1 }
  return 42
}

check_s := fn(p : ptr(mut Rec)) -> u64 {
  if deref(p).s / 2 == 0 - 42 { return 22 }
  return 1
}

main := fn() -> u64 {
  mut r := Rec(u = 18446744073709551615, s = 0 - 84)
  check_u(ptr(mut r)) + check_s(ptr(mut r))
}
