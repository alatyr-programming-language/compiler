Pair := struct { a : u16, b : u16 }

take_pair := @extern @abi(c) fn(p : Pair) -> i64

main := fn() -> u64 {
  p := Pair(a = 7, b = 5)
  u64(take_pair(p))
}
