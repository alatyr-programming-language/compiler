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
Hd := brand(usize)
mut SEEN : u64 = 0
to_hd := @convert fn(n : usize) -> Hd {
  comptime if verify.checked { SEEN = 1 } else { SEEN = 2 }
  Hd(n)
}
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
## The pointer of `unchecked deref(…)` is evaluated inside the region: the mode-polymorphic conversion
## in it takes its unchecked instance (Comptime §7.5), so `SEEN` is 2 (an earlier draft gave 1).
rdm := fn(h : usize) -> u64 {
  mut v : [u64; 2] = [0, 0]
  v = unchecked deref(bitcast(ptr([u64; 2]), usize(Hd(h))))
  v[0] + v[1] + SEEN - 28
}
## A declaration whose `:` follows on the next line is still the declaration in
## effect (round-6 review: an array copy into the scalar gave 40 where 42 was due). The pointee is
## 40 + 2 * 2^32, so a scalar holding the whole word sums its halves to 42.
rdy := fn(hq : usize) -> u64 {
  q : ptr(u64) = unchecked bitcast(ptr(u64), hq)
  mut v : [u8; 8] = [0, 0, 0, 0, 0, 0, 0, 0]
  mut r : u64 = 0
  if hq != 0 {
    mut v
      : u64 = 0
    v = deref(q)
    r = (v % 4294967296) + (v / 4294967296)
  }
  r + u64(v[0]) - 42
}
rdy2 := fn(hq : usize) -> u64 {
  mut r : u64 = 0
  for i in 0..1 {
    mut v : [u8; 3] = [1, 1, 1]
    r = u64(v[0]) - 1
  }
  q : ptr(u64) = unchecked bitcast(ptr(u64), hq)
  mut v
    : u64 = 0
  v = deref(q)
  r + (v % 4294967296) + (v / 4294967296) - 42
}
## A reassignment is not a declaration: the array reassigned twice keeps its `[u64; 2]` copy, and a
## scalar `v` after a loop-scoped array `v`, assigned and compound-assigned before `v = deref(q)`, keeps
## its one-word store (round-7 review: both were refused).
rdz2 := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  mut v : [u64; 2] = [0, 0]
  v = deref(p)
  v = deref(p)
  v[0] + v[1] - 26
}
rds2 := fn(h : usize) -> u64 {
  mut r : u64 = 0
  for i in 0..1 {
    mut v : [u8; 3] = [1, 1, 1]
    r = u64(v[0]) - 1
  }
  q : ptr(u64) = unchecked bitcast(ptr(u64), h)
  mut v : u64 = 0
  v = 5
  v += 5
  v = deref(q)
  r + v - 21
}
## A scalar declared with a `#` comment before its `:` or its `:=` keeps its one-word store: only an
## unread ARRAY annotation is refused (#1859; round-9 review: these were refused).
rdk := fn(h : usize) -> u64 {
  q : ptr(u64) = unchecked bitcast(ptr(u64), h)
  v # the scalar
    : u64 = deref(q)
  w # inferred
    := deref(q)
  v + w - 397828
}
rdk2 := fn(h : usize) -> u64 {
  q : ptr(u64) = unchecked bitcast(ptr(u64), h)
  mut r : u64 = 0
  for i in 0..1 {
    mut v : [u8; 3] = [1, 1, 1]
    r = u64(v[0]) - 1
  }
  v # the scalar, over the loop's array
    : u64 = deref(q)
  r + v - 198914
}
## An array type written with a prefix attribute is the same `[T; N]` (Grammar §3.3, Types §8): its
## reassignment copies both elements (round-10 review: 40 where 42 is due).
rdg := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  mut v : @align(16) [u64; 2] = [0, 0]
  v = deref(p)
  v[0] + v[1] - 26
}
## Blanks between the tokens of an attribute do not change the type (Grammar §1; round-11 review: the
## declaration moved one word).
rde := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  v : @align (16) [u64; 2] = deref(p)
  w : @ align(16) [u64; 2] = deref(p)
  v[0] + v[1] + w[0] + w[1] - 52
}
## A pointer to an array, declared with a prefix attribute from `deref`, is one word (Types §8; round-12
## review: it was refused).
rdf := fn(h : usize) -> u64 {
  pp : ptr(ptr([u64; 2])) = unchecked bitcast(ptr(ptr([u64; 2])), h)
  v : @align(16) ptr([u64; 2]) = deref(pp)
  a : [u64; 2] = deref(v)
  a[0] + a[1] - 26
}
main := fn() -> u64 {
  mut arr : [u64; 2] = [21, 5]
  mut wv : u64 = 198914
  ha := unchecked bitcast(usize, ptr(arr))
  hb := unchecked bitcast(usize, ptr(wv))
  mut wq : u64 = 8589934632
  hq := unchecked bitcast(usize, ptr(wq))
  mut pa : ptr([u64; 2]) = ptr(arr)
  hp := unchecked bitcast(usize, ptr(pa))
  rda(ha) + rdr(ha) + rdb(hb) + rdc(hb) + rdz(ha) + rds(ha) + rdw(ha) + rdt(ha) + rdu(ha) + rdp(hp) + rdi(ha) + rdx(ha, hb) + rdm(ha) + rdy(hq) + rdy2(hq) + rdz2(ha) + rds2(ha) + rdk(hb) + rdk2(hb) + rdg(ha) + rde(ha) + rdf(hp)
}
## expect: run 42
