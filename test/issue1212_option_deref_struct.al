## e2e / issue #1212 — `Option(S).Some(deref(p))` of a multi-word struct `S` keeps every word.
##
## `vec::get`, `vec::try_at` and `vec::pop` build their result as `Option(T).Some(deref(elem))`. A
## `deref(p)` payload is neither a literal nor a local, so the enum emitter took it for a scalar and
## delivered the struct's word 0 alone: the later fields read stale registers (`S3`'s `c` read 48). The
## store into a local (`o := Option(S3).Some(deref(p))`) dropped the same words.
##
## Covered: the three `Vec` reads over a three-word struct and a `{u64, u32}` struct, a generic and a
## concrete user function returning `Some(deref(p))` through a pointer parameter, and the local store.
## Each check owns a code from 100 up; 42 means every field arrived.
##
## Parent `992bd767` (x86_64, omen): built rc 0 and returned 100 where 42 was due.
S3 := struct { a : u64, b : u64, c : u64 }
S2 := struct { a : u64, b : u32 }

g := fn(T : type, p : ptr(T)) -> Option(T) { Option(T).Some(deref(p)) }
h := fn(p : ptr(S3)) -> Option(S3) { Option(S3).Some(deref(p)) }

sum3 := fn(o : Option(S3)) -> u64 {
  match o {
    Some(x) => { x.a * 100 + x.b * 10 + x.c }
    None => { 999 }
  }
}
sum2 := fn(o : Option(S2)) -> u64 {
  match o {
    Some(x) => { x.a * 10 + u64(x.b) }
    None => { 999 }
  }
}

main := fn() -> u64 {
  s := S3(a = 1, b = 2, c = 3)
  t := S2(a = 7, b = 9)
  og3 := g(S3, ptr(s))
  if sum3(og3) != 123 { return 100 }
  oh3 := h(ptr(s))
  if sum3(oh3) != 123 { return 101 }
  og2 := g(S2, ptr(t))
  if sum2(og2) != 79 { return 102 }
  p := ptr(s)
  ol := Option(S3).Some(deref(p))
  if sum3(ol) != 123 { return 103 }
  match std::os::arena(65536) {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      mut v := alloc::vec::with_capacity(S3, ptr(mut ar), 4)
      r0 := alloc::vec::push(S3, v, S3(a = 1, b = 2, c = 3))
      r1 := alloc::vec::push(S3, v, S3(a = 4, b = 5, c = 6))
      og := alloc::vec::get(S3, ptr(v), 0)
      if sum3(og) != 123 { return 110 }
      ot := alloc::vec::try_at(S3, ptr(v), 1)
      if sum3(ot) != 456 { return 111 }
      op := alloc::vec::pop(S3, v)
      if sum3(op) != 456 { return 112 }
      mut w := alloc::vec::with_capacity(S2, ptr(mut ar), 4)
      r2 := alloc::vec::push(S2, w, S2(a = 7, b = 9))
      o2 := alloc::vec::try_at(S2, ptr(w), 0)
      if sum2(o2) != 79 { return 113 }
      on := alloc::vec::get(S3, ptr(v), 5)
      if sum3(on) != 999 { return 114 }
    }
    Err(_) => { return 120 }
  }
  42
}
