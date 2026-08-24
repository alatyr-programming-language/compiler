## FFI: bounded SysV INTEGER packing for a by-value C struct with two u8 fields.
## The C layout is two bytes in one eightbyte: 44 + 263*1 = 307. Before the
## caller-side packing fix, the compiler passes the two internal words in %rdi/%rsi;
## C therefore observes only the low byte of %rdi and returns 44.
Pair := struct { a : u8, b : u8 }

sumbytes := @extern @abi(c) fn(p : Pair) -> i64

main := fn() -> u64 {
  p := Pair(a = 44, b = 1)
  return u64(sumbytes(p))
}
