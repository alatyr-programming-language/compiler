## Issue #168: C calls an exported Alatyr function with a two-u8 struct argument and receives it back.
## Alatyr reads both incoming fields; C reads both returned fields. This is the receiving-side mirror
## of issue168_u8_pair_to_c and covers the same exact packed shape.
Pair := struct { a : u8, b : u8 }

@export("al_echo_u8_pair") al_echo_u8_pair := @abi(c) fn(p : Pair) -> Pair {
  if u64(p.a) * 4 + u64(p.b) * 8 != 68 { return Pair(a = 0, b = 0) }
  return p
}

drive := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  u64(drive())
}
