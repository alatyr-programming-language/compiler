## IR-37 (#1786): a struct whose fields are narrower than a word, reached through a pointer. The layout
## gives each field a word of its own (`lower_layout::field_byte_place`: field `i` at byte `8 * i`), and
## the legacy emitters that build such an access move that whole word (x86_64, aarch64; riscv64 and
## wasm trap). `put`, `chk` and `whole` are built from the shared IR; `lput` and `lchk` hold a float
## local, which keeps them on the legacy emitter, so memory crosses in both directions.
##   1. legacy `lput` writes, the IR's `chk` reads: the narrow loads and their sign extension;
##   2. the IR's `put` writes over it, legacy `lchk` reads the whole words: a signed field that `lput`
##      left negative is now positive, so a store of the low bytes alone would leave the old sign bits
##      above them and `lchk` would read a different value;
##   3. the IR copies the pointee whole (`v : N = deref(p)`) and reads the copy.
## `g` is never written through the pointer: it checks that no write reached a neighbour.
N := struct { a : u8, b : i8, c : u16, d : i16, e : u32, f : i32, g : u64, h : bool }
lput := fn(p : ptr(mut N)) {
  z : f64 = 1.0
  deref(p).a = 17
  deref(p).b = -3
  deref(p).c = 1000
  deref(p).d = -2
  deref(p).e = 7
  deref(p).f = -5
  deref(p).h = true
}
put := fn(p : ptr(mut N)) {
  p.a = 200
  p.b = 100
  deref(p).c = 60000
  deref(p).d = 30000
  p.e = 4000000000
  deref(p).f = 70000
  p.h = false
}
## The values `lput` wrote, read by the IR.
chk := fn(p : ptr(N)) -> u64 {
  if p.a != 17 { return 1 }
  if p.b != -3 { return 2 }
  if deref(p).c != 1000 { return 3 }
  if deref(p).d != -2 { return 4 }
  if p.e != 7 { return 5 }
  if p.f != -5 { return 6 }
  if p.g != 77 { return 7 }
  if not p.h { return 8 }
  0
}
## The values `put` wrote, read by legacy code.
lchk := fn(p : ptr(N)) -> u64 {
  z : f64 = 2.0
  if deref(p).a != 200 { return 1 }
  if deref(p).b != 100 { return 2 }
  if deref(p).c != 60000 { return 3 }
  if deref(p).d != 30000 { return 4 }
  if deref(p).e != 4000000000 { return 5 }
  if deref(p).f != 70000 { return 6 }
  if deref(p).g != 77 { return 7 }
  if deref(p).h { return 8 }
  0
}
## The pointee copied whole, then read field by field.
whole := fn(p : ptr(N)) -> u64 {
  v : N = deref(p)
  if v.b != 100 or v.d != 30000 or v.f != 70000 or v.g != 77 or v.h { return 1 }
  0
}
main := fn() -> u64 {
  mut s := N(a = 0, b = 0, c = 0, d = 0, e = 0, f = 0, g = 77, h = false)
  lput(ptr(mut s))
  r1 := chk(ptr(s))
  if r1 != 0 { return r1 }
  put(ptr(mut s))
  r2 := lchk(ptr(s))
  if r2 != 0 { return 10 + r2 }
  r3 := whole(ptr(s))
  if r3 != 0 { return 20 + r3 }
  42
}
## expect: run 42
