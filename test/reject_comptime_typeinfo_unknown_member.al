## Unknown TypeInfo field members must fail loudly instead of entering runtime field lowering.
B := struct { a : u64 }

query := fn(T : type, value : T) -> u64 {
  mut total : u64 = 0
  comptime for f in typeinfo(T).fields { total = total + f.unknown }
  total
}

main := fn() -> u64 { query(B, B(a = 1)) }
