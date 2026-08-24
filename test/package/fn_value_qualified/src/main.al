apply := fn(f : fn(u64) -> u64, x : u64) -> u64 { f(x) }

main := fn() -> u64 {
  direct := hex::encode(40)
  indirect := apply(hex::encode, 40)
  if direct == 41 and indirect == 41 { 42 } else { 0 }
}
