## e2e (a64 SRET, TRAILING value — LOCAL variant) — a wide-struct-returning fn whose body ENDS in a
## struct LOCAL variable with NO explicit `return` (the other emit_a64_sret_store sub-path: copy the
## local's frame slots through the x8 indirect-result pointer, vs the struct-literal path). `mk` builds
## a 9-word S9 (fields base+0..base+8) and its trailing value is the local `v`. `main` reads fields at
## distinct non-zero offsets: (a=10)+(i=18) + ((e=14)-(b=11)) = 28 + 3 = 31. x86_64 already handles this.
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
mk := fn(base : u64) -> S9 {
  v := S9(a = base, b = base + 1, c = base + 2, d = base + 3, e = base + 4, f = base + 5, g = base + 6, h = base + 7, i = base + 8)
  v
}
main := fn() -> u64 {
  s := mk(10)
  return (s.a + s.i) + (s.e - s.b)
}
