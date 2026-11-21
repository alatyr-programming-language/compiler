## Issue #1809 — copying a whole fixed array out of a pointer, both as a declaration
## (`v : [u64; 2] = deref(p)`) and as a reassignment of a local declared `[T; N]` (`u = deref(p)`).
## Memory §4.3: `deref(p)` in value context loads the place it denotes, and Types §6.4 makes `[T; N]` a
## value of `N` contiguous elements, so the local holds every element and its `.len` is `N`. x86_64 moved
## one word and read a value that changed from run to run (216, 24, 56, 72 measured), with `v.len` 0, and
## the reassignment moved one word into the declared block; aarch64, riscv64 and wasm trapped. A byte
## element copies the same way, into the packed byte block. A `[T; 0]` is zero-sized (Types §6.5): its copy
## moves nothing, its `.len` is 0, and its neighbours keep their values (x86_64 answered 44 for 42 here).
## Due 42: 5 + 2 from the declared words, 21 from the reassigned words, 2 + 3 from the declared bytes, 9
## from the reassigned bytes, 0 from the zero-length copy. The bytes come from a `u64` local, whose little-endian bytes are 2, 9, 3, 0,
## … (x86_64 takes `ptr` of a local `[u8; N]` one word low, #1812).
## aarch64, riscv64 and wasm refuse both forms at compile time until they copy them (#1811).
## spec: Memory §4.3; Types §6.4
rda := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  v : [u64; 2] = deref(p)
  v[1] + v.len
}
rdr := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  mut u : [u64; 2] = [0, 0]
  u = deref(p)
  u[0]
}
rdb := fn(h : usize) -> u64 {
  p : ptr([u8; 3]) = unchecked bitcast(ptr([u8; 3]), h)
  w : [u8; 3] = deref(p)
  u64(w[0]) + u64(w[2])
}
rdc := fn(h : usize) -> u64 {
  p : ptr([u8; 3]) = unchecked bitcast(ptr([u8; 3]), h)
  mut z : [u8; 3] = [0, 0, 0]
  z = deref(p)
  u64(z[1])
}
rdz := fn(h : usize) -> u64 {
  p : ptr([u64; 0]) = unchecked bitcast(ptr([u64; 0]), h)
  mut before : u64 = 7
  v : [u64; 0] = deref(p)
  mut after : u64 = 9
  before + after + v.len - 16
}
main := fn() -> u64 {
  mut arr : [u64; 2] = [21, 5]
  mut wv : u64 = 198914
  ha := unchecked bitcast(usize, ptr(arr))
  hb := unchecked bitcast(usize, ptr(wv))
  rda(ha) + rdr(ha) + rdb(hb) + rdc(hb) + rdz(ha)
}
## expect: run 42
