## e2e — `Option::map` / `Option::and_then` via IMPLICIT UFCS `o.map(f)` (Stdlib §160). A 2-type-param
## generic reached WITHOUT explicit type-args: `T` comes from the receiver's declared type (`Option(u64)`),
## and `U` (the mapper's return, absent from the receiver) is recovered from the fn ARGUMENT's declared
## return type. The explicit-type-arg form (`map(T, U, o, f)`) stays available (see option_map.al).
## Returns 42.
dbl := fn(x : u64) -> u64 { return x + x }
chk := fn(x : u64) -> Option(u64) {
  if x > 100 { return Option(u64).None }
  return Option(u64).Some(x + 1)
}

main := fn() -> u64 {
  os : Option(u64) = Option.Some(21)
  on : Option(u64) = Option.None
  mut a : u64 = 0
  mut b : u64 = 0
  mut c : u64 = 0

  ## map — Some(21) → Some(42)
  om := os.map(dbl)
  match om { Option::Some(v) => { a = v } Option::None => { a = 500 } }

  ## map — None stays None
  onm := on.map(dbl)
  match onm { Option::Some(v) => { b = 500 } Option::None => { b = 7 } }

  ## and_then — Some(21) → chk → Some(22)
  oat := os.and_then(chk)
  match oat { Option::Some(v) => { c = v } Option::None => { c = 500 } }

  if a == 42 and b == 7 and c == 22 { return 42 }
  1
}
