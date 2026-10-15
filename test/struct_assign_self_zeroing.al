## #909, the zeroing writers: a @packed struct and a standard-byte-layout struct (sub-word scalar
## fields) are written by x86_64's legacy emitter after it ZEROES the whole destination, so a literal
## whose FIRST initializer reads the variable it is assigned to read zeroes. Such a literal is now built
## in a temp block and copied. Right: p = (4, 8), q = (7, 15) -> 4 + 16 + 7 + 15 = 42. Measured on
## omen: the 0.2.15 seed's x86_64 answers 31; aarch64, riscv64 and wasm (shared IR) answer 42.
Pk := @packed struct { a : u8, b : u32 }
By := struct { a : u8, b : u16 }
main := fn() -> u64 {
  mut p := Pk(a = 3, b = 4)
  p = Pk(a = p.a + 1, b = p.b * 2)
  mut q := By(a = 5, b = 6)
  q = By(a = q.a + 2, b = q.b + 9)
  u64(p.a) + u64(p.b) * 2 + u64(q.a) + u64(q.b)
}
