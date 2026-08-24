## FFI: a MEMORY-class struct-by-value ARG at an @abi(c) call (spec 150 §FN-9, increment 3a). sumbig
## lives in test/ffi/struct_big_arg.c. SysV classes a struct > 16 bytes (Big = 24 bytes, three
## eightbytes) as MEMORY — passed BY VALUE ON THE STACK: the caller reserves a 16-aligned stack
## argument area and copies b.a/b.b/b.c into 0/8/16(%rsp), and the callee reads them there. sumbig
## returns b.a + b.b - b.c (ORDER/VALUE-sensitive: a mis-copied stack slot yields a wrong exit).
Big := struct { a : i64, b : i64, c : i64 }

sumbig := @extern @abi(c) fn(b : Big) -> i64

main := fn() -> u64 {
  b := Big(a = 50, b = 17, c = 25)   ## sumbig -> 50 + 17 - 25 = 42
  return u64(sumbig(b))
}
