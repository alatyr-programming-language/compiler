## IR-41 (#1786): a struct RESULT whose fields are narrower than a word, one word each, crossing between
## IR-built and legacy-emitted functions in both directions. The `u64` field keeps it in the WORD tier
## (a struct of narrow scalars alone is laid out byte-exactly, which the convention does not take). `mk` and `rd` are built from the shared IR;
## `lmk` and `lrd` hold a float local, which keeps them on the legacy emitter.
##   1. the IR's `mk` writes negative signed fields over a zeroed literal, at their own width; the legacy
##      `lrd` reads each word whole, so the result must carry every narrow field as its canonical word;
##   2. the legacy `lmk` returns its words, the IR's `rd` reads each field at its width;
##   3. an IR caller of the IR's `mk`, and a field of a call result read in place (`mk(1).e`).
N := struct { a : u8, b : i8, c : u16, d : i16, e : i32, h : bool, g : u64 }
mk := fn(k : u64) -> N {
  mut s := N(a = 0, b = 0, c = 0, d = 0, e = 0, h = false, g = 0)
  s.a = 200
  s.b = -3
  s.c = 60000
  s.d = -2
  s.e = -5
  s.h = k == 1
  s.g = 77
  s
}
lmk := fn(k : u64) -> N {
  z : f64 = 1.0
  N(a = 17, b = -100, c = 1000, d = -30000, e = 70000, h = k == 1, g = 66)
}
## The legacy reader of the IR's result.
lrd := fn() -> u64 {
  z : f64 = 2.0
  n := mk(1)
  if n.a != 200 { return 1 }
  if n.b != -3 { return 2 }
  if n.c != 60000 { return 3 }
  if n.d != -2 { return 4 }
  if n.e != -5 { return 5 }
  if not n.h { return 6 }
  if n.g != 77 { return 7 }
  0
}
## The IR reader of the legacy result, then of its own.
rd := fn() -> u64 {
  n := lmk(1)
  if n.a != 17 { return 1 }
  if n.b != -100 { return 2 }
  if n.c != 1000 { return 3 }
  if n.d != -30000 { return 4 }
  if n.e != 70000 { return 5 }
  if not n.h { return 6 }
  if n.g != 66 { return 9 }
  m := mk(0)
  if m.b != -3 or m.d != -2 or m.e != -5 or m.h { return 7 }
  if mk(1).e != -5 { return 8 }
  0
}
main := fn() -> u64 {
  r1 := lrd()
  if r1 != 0 { return r1 }
  r2 := rd()
  if r2 != 0 { return 10 + r2 }
  42
}
## expect: run 42
