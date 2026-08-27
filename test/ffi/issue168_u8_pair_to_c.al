## Issue #168: Alatyr calls a C function with a two-u8 struct argument and receives the same struct.
## C reads both argument fields; Alatyr reads both returned fields. The packed two-byte image must
## occupy one SysV INTEGER eightbyte in both directions of this call edge.
Pair := struct { a : u8, b : u8 }

echo_pair := @extern @abi(c) fn(p : Pair) -> Pair

main := fn() -> u64 {
  p := Pair(a = 7, b = 5)
  q := echo_pair(p)
  u64(q.a) * 4 + u64(q.b) * 8
}
