## e2e / issue #987 — an implicit generic call through a pointer receiver builds when its callee's
## qualified name is long.
##
## The lowerer completes `bx.bget()` into the explicit `<module>::bget(u8, bx)`, qualifying the callee by
## its declaration's module, which for a single file is the file's stem. That name was built in a fixed
## 64-byte buffer, so a module path past 56 bytes stopped the compiler with `rt: StrBuf overflow` on a
## valid program. This file's stem alone is 56 bytes: the qualified `…::bget` is 62.
##
## Each check owns a code from 100 up; 42 means all held.
##
## Parent `9f226e69` (x86_64, omen): the build fails, `rt: StrBuf overflow`.
Box := fn(T : type) -> type { struct { v : T, tag : u64 } }
bget := fn(T : type, b : ptr(Box(T))) -> T { deref(b).v }

main := fn() -> u64 {
  k : u8 = 40
  bx : Box(u8) = Box(u8)(v = k, tag = 9)
  x : u8 = bx.bget()
  if x != 40 { return 100 }
  w : Box(u64) = Box(u64)(v = 2, tag = 9)
  y : u64 = w.bget()
  if y != 2 { return 101 }
  u64(x) + y
}

## expect: run 42
