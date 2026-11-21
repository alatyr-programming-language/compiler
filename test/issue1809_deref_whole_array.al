## Issue #1809 — copying a whole fixed array out of a pointer, both as a declaration
## (`v : [u64; 2] = deref(p)`) and as a reassignment of a local declared `[T; N]` (`u = deref(p)`).
## Memory §4.3: `deref(p)` in value context loads the place it denotes, and Types §6.4 makes `[T; N]` a
## value of `N` contiguous elements, so the local holds every element and its `.len` is `N`. x86_64 moved
## one word and read a value that changed from run to run (216, 24, 56, 72 measured), with `v.len` 0, and
## the reassignment moved one word into the declared block; aarch64, riscv64 and wasm trapped. A byte
## element copies the same way, into the packed byte block. A `[T; 0]` is zero-sized (Types §6.5): its copy
## moves nothing, its `.len` is 0, and its neighbours keep their values (x86_64 answered 44 for 42 here).
## Due 42: 5 + 2 from the declared words, 21 from the reassigned words, 2 + 3 from the declared bytes, 9
## from the reassigned bytes, 0 from the zero-length copy, 0 from each scalar or pointer named like an earlier array. The bytes come
## from a `u64` local, whose little-endian bytes are 2, 9, 3, 0, … (x86_64 takes `ptr` of a local `[u8; N]` one word low, #1812).
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
## A scalar `v` declared after an array `v` of the same name keeps its one-word store: the copy reads the
## binding the store writes, not the last array of that name (an earlier draft of #1821 copied into the
## dead `[u8; 3]` block and left the scalar 0).
rds := fn(h : usize) -> u64 {
  mut r : u64 = 0
  for i in 0..1 {
    mut v : [u8; 3] = [1, 1, 1]
    r = u64(v[0]) - 1
  }
  q : ptr(u64) = unchecked bitcast(ptr(u64), h)
  mut v : u64 = 0
  v = deref(q)
  r + v - 21
}
## The same with the two `v` in sibling `if` blocks (round-2 probe w1).
rdw := fn(h : usize) -> u64 {
  mut r : u64 = 0
  if h != 0 {
    mut v : [u8; 3] = [1, 1, 1]
    r = u64(v[0]) - 1
  }
  if h != 0 {
    q : ptr(u64) = unchecked bitcast(ptr(u64), h)
    mut v : u64 = 0
    v = deref(q)
    r = r + v - 21
  }
  r
}
## A wider earlier array of the same name (8 and 16 bytes, probes t2 and t4).
rdt := fn(h : usize) -> u64 {
  mut r : u64 = 0
  for i in 0..1 {
    mut v : [u8; 8] = [0, 0, 0, 0, 0, 0, 0, 0]
    r = u64(v[7])
  }
  q : ptr(u64) = unchecked bitcast(ptr(u64), h)
  mut v : u64 = 0
  v = deref(q)
  r + v - 21
}
rdu := fn(h : usize) -> u64 {
  mut r : u64 = 0
  for i in 0..1 {
    mut v : [u8; 16] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    r = u64(v[15])
  }
  q : ptr(u64) = unchecked bitcast(ptr(u64), h)
  mut v : u64 = 0
  v = deref(q)
  r + v - 21
}
## A pointer `v` after an array `v` (probes s2, s3): its declaration and its reassignment each move the
## one pointer word.
rdp := fn(hp : usize) -> u64 {
  mut r : u64 = 0
  for i in 0..1 {
    mut v : [u64; 2] = [0, 0]
    r = v[1]
  }
  pp : ptr(ptr([u64; 2])) = unchecked bitcast(ptr(ptr([u64; 2])), hp)
  mut v : ptr([u64; 2]) = deref(pp)
  v = deref(pp)
  x : [u64; 2] = deref(v)
  r + x[0] + x[1] - 26
}
## Signed and `usize` word elements reassigned into literal-declared arrays: the frame block's element
## tier and count match the copy's, so it is taken (an unmatched block is refused, #1847).
rdi := fn(h : usize) -> u64 {
  p : ptr([i64; 2]) = unchecked bitcast(ptr([i64; 2]), h)
  mut v : [i64; 2] = [0, 0]
  v = deref(p)
  q : ptr([usize; 2]) = unchecked bitcast(ptr([usize; 2]), h)
  mut w : [usize; 2] = [0, 0]
  w = deref(q)
  u64(v[0] + v[1]) + u64(w[1]) - 31
}
## `unchecked deref(p)` yields the same whole array (Grammar §3.7): a word reassignment and a byte
## declaration (an earlier draft of #1821 moved one word, 40 where 42 was due).
rdx := fn(h : usize, hb : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  mut v : [u64; 2] = [0, 0]
  v = unchecked deref(p)
  b : ptr([u8; 3]) = unchecked bitcast(ptr([u8; 3]), hb)
  w : [u8; 3] = unchecked deref(b)
  v[0] + v[1] + u64(w[0]) + u64(w[1]) + u64(w[2]) - 40
}
main := fn() -> u64 {
  mut arr : [u64; 2] = [21, 5]
  mut wv : u64 = 198914
  ha := unchecked bitcast(usize, ptr(arr))
  hb := unchecked bitcast(usize, ptr(wv))
  mut pa : ptr([u64; 2]) = ptr(arr)
  hp := unchecked bitcast(usize, ptr(pa))
  rda(ha) + rdr(ha) + rdb(hb) + rdc(hb) + rdz(ha) + rds(ha) + rdw(ha) + rdt(ha) + rdu(ha) + rdp(hp) + rdi(ha) + rdx(ha, hb)
}
## expect: run 42
