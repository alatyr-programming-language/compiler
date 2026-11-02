## #1307 — a store or load through a local whose type is `ptr(mut K)`, inside a generic instance at
## `K = i8`, used the width and sign of the unsubstituted `K` (a word, unsigned): `deref(kd) = k`
## wrote eight bytes over the seven slots after it, and `deref(ks)` read eight bytes without sign
## extension. alloc::omap / alloc::oset move their keys this way (`omap_insert`, `omap_grow`), so
## `OMap(i8, _)` and `OSet(i8)` lost keys (container matrix cells omap.key.i8,
## oset.insert_contains.i8).
## NON-VACUOUS: the parent (origin/main da18fef2) exits 10.
## `w` is the element width the caller states, so the instances need no `size(K)`.
put := fn(K : type, base : usize, w : usize, i : usize, k : K) {
  kd := unchecked bitcast(ptr(mut K), base + i * w)
  deref(kd) = k
}

get := fn(K : type, base : usize, w : usize, i : usize) -> K {
  ks := unchecked bitcast(ptr(mut K), base + i * w)
  deref(ks)
}

## Move slot `i` to slot `j` through two instance-typed locals, as `omap_grow` does.
mv := fn(K : type, base : usize, w : usize, i : usize, j : usize) {
  ks := unchecked bitcast(ptr(mut K), base + i * w)
  kd := unchecked bitcast(ptr(mut K), base + j * w)
  deref(kd) = deref(ks)
}

main := fn() -> u64 {
  ## Two words of i8 slots, then two words of u16 slots, all zero.
  mut buf : [u64; 4] = [0, 0, 0, 0]
  b := unchecked bitcast(usize, ptr(buf))
  mut i : usize = 0
  while i < 8 {
    put(i8, b, 1, i, 0 - i8(i) - 1)
    i += 1
  }
  ## Eight one-byte stores fill the first word; every slot survives the stores after it.
  if get(i8, b, 1, 0) != 0 - 1 { return 10 }
  if get(i8, b, 1, 3) != 0 - 4 { return 11 }
  ## A negative i8 reads back sign-extended.
  x := get(i8, b, 1, 7)
  if x != 0 - 8 { return 12 }
  if i64(x) != 0 - 8 { return 13 }
  mv(i8, b, 1, 2, 5)
  if get(i8, b, 1, 5) != 0 - 3 { return 14 }
  if get(i8, b, 1, 6) != 0 - 7 { return 15 }
  ## The u16 instance stays two bytes wide.
  put(u16, b + 16, 2, 0, 513)
  put(u16, b + 16, 2, 1, 65535)
  if get(u16, b + 16, 2, 0) != 513 { return 16 }
  if get(u16, b + 16, 2, 1) != 65535 { return 17 }
  42
}
## expect: run 42
