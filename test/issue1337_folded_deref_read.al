## e2e / issue #1337 — a niche-folded `Option(ptr(T))` read through a pointer IS the one folded word.
##
## Memory §4.2/§4.6: `Option(ptr(T))` lowers identically to a raw pointer-width value, `None` is the
## all-zero niche, and `deref(p)` in value context loads that word. The lowering folded a folded value
## by its FORM — a variant literal, a folded local or parameter, a call result, an array element, a
## field read — and a plain `deref(p)` was none of them. So `v := deref(p)` bound an untyped scalar
## word, and both `pkey(v)` and `pkey(deref(p))` pushed that WORD to the by-reference `Option`
## parameter, which read its one word THROUGH the pointer it received: the stored address `base + 64`
## became the block address, the memory there was read as the discriminant, and `match o` took
## `Option::None` for a stored `Some(q)`. Only the ANNOTATED binding worked, because its slot carried
## the folded span and so passed by reference.
##
## Each check owns its own code, so a wrong value, a `None` for a `Some` and a trap stay distinguishable.
## Parent `58a80376` (x86_64, omen): built rc 0 and returned 10 where 42 was due.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

pkey := fn(o : Option(ptr(u64))) -> usize {
  match o {
    Option::Some(q) => { return unchecked bitcast(usize, q) }
    Option::None => { return 1 }
  }
}

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 4096, 3, 34, bitcast(usize, 0 - 1), 0)
  base := unchecked bitcast(usize, r)
  p := unchecked bitcast(ptr(mut Option(ptr(u64))), base)
  q := unchecked bitcast(ptr(mut usize), base)
  deref(q) = base + 64
  ## (1) the unannotated binding: `v` is the folded word, and passes to a by-ref Option param by reference
  v := deref(p)
  if pkey(v) != base + 64 { return 10 }
  ## (2) the same read passed straight as an argument: it has no frame home, so it is staged
  if pkey(deref(p)) != base + 64 { return 11 }
  ## (3) the annotated binding, right at the parent, stays right
  w : Option(ptr(u64)) = deref(p)
  if pkey(w) != base + 64 { return 12 }
  ## (4) the niche: a zero word in the same slot reads back `None`, both ways
  deref(q) = 0
  if pkey(deref(p)) != 1 { return 13 }
  n := deref(p)
  if pkey(n) != 1 { return 14 }
  42
}

## expect: run 42
