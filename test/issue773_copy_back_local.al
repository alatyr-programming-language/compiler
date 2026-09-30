## Issue #773 — a local copied into another local and back (`b := a` then `a = b`) crashed the aarch64
## and riscv64 COMPILERS with SIGSEGV (exit 139, nothing on stderr); x86_64 and wasm built and ran it.
## The twins' struct-type scan of a local (`a64_local_struct_ns`/`_nl`, `rv_local_struct_ns`/`_nl`)
## kept scanning past the local's non-struct declaration, took the REASSIGNMENT `a = b` as a type
## source and recursed `a -> b -> a` until the stack overflowed. Only a declaration now decides. Each
## shape progen reduced to is here: the copy back (u64 and i64), the swap of two locals initialised
## separately, the same body in a helper that is never called, a copy of a parameter's copy, an
## explicitly uninitialised local (`mut a : u64` then `a = 4`) copied back, and a struct copied back,
## whose type the scan must still resolve through the copy. The program answers 42 on all four backends.
P := struct { x : u64, y : u64 }
unused := fn(p : u64) -> u64 {
  mut v : u64 = p
  mut w : u64 = v
  v = w
  7
}
signed_back := fn() -> i64 {
  mut v : i64 = 0 - 3
  mut w : i64 = v
  v = w
  v + w
}
swap := fn() -> u64 {
  mut a : u64 = 5
  mut b : u64 = 9
  a = b
  b = a
  a + b
}
param_back := fn(a : u64) -> u64 {
  mut x : u64 = a
  y : u64 = x
  x = y
  x + y
}
uninit_back := fn() -> u64 {
  mut a : u64
  a = 4
  b : u64 = a
  a = b
  a + b
}
struct_back := fn() -> u64 {
  mut p : P = P(x = 1, y = 2)
  q := p
  p = q
  p.x + q.y
}
main := fn() -> u64 {
  mut a : u64 = 1
  b : u64 = a
  a = b
  if signed_back() != 0 - 6 { return 2 }
  if swap() != 18 { return 3 }
  if struct_back() != 3 { return 4 }
  if param_back(6) != 12 { return 5 }
  if uninit_back() != 8 { return 6 }
  a + 41
}
