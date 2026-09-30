## e2e / issue #808 — an array whose elements are `Option(ptr(T))`.
##
## `Option(ptr(T))` is one folded word (None = 0, Some(p) = p) in every position (Types §6.2/§8), so
## `[Option(ptr(T)); N]` is N words. The array paths sized the element from the FIRST literal element,
## and a bare `Option.None` names no type argument, so the element became a two-word `[disc, payload]`
## over a bare `Option`: the payload lost its pointee and `deref(q).v` of a matched element read 0 on a
## clean build. The element store pushed the scalar `0` placeholder for a `Some` literal, and the element
## read did not see a folded value. The declared element type now decides the one-word element in the
## literal, the element store and the element read, for a local array, an array parameter (by value and
## `in out`) and an array field.
##
## 42 means every element held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
T := struct { n : u64, b : [Option(ptr(mut N)); 2], m : u64 }

val := fn(o : Option(ptr(mut N))) -> u64 { match o { Some(q) => { return deref(q).v }; None => { return 0 } }; 0 }

## an array parameter read element by element
sum3 := fn(xs : [Option(ptr(mut N)); 3]) -> u64 {
  mut s : u64 = 0
  mut i : usize = 0
  while i < 3 { o : Option(ptr(mut N)) = xs[i]; s = s + val(o); i = i + 1 }
  s
}

## an element stored through an `in out` array parameter
put := fn(in out xs : [Option(ptr(mut N)); 3], k : usize, q : ptr(mut N)) { xs[k] = Option.Some(q) }

main := fn() -> u64 {
  mut b := N(v = 40, next = Option.None)
  mut c := N(v = 2, next = Option.None)
  ## the literal, then a read into a local and a direct match
  xs : [Option(ptr(mut N)); 3] = [Option.Some(ptr(mut b)), Option.None, Option.Some(ptr(mut c))]
  o : Option(ptr(mut N)) = xs[0]
  if val(o) != 40 { return 100 }
  match xs[1] { Some(_q) => { return 101 }; None => {} }
  match xs[2] { Some(q) => { if deref(q).v != 2 { return 102 } }; None => { return 103 } }
  ## iteration and a by-value parameter
  mut s : u64 = 0
  for e in xs { s = s + val(e) }
  if s != 42 { return 104 }
  if sum3(xs) != 42 { return 105 }
  ## element stores, bare and typed heads, and an `in out` parameter
  mut ys : [Option(ptr(mut N)); 3] = [Option.None, Option.None, Option.None]
  ys[0] = Option.Some(ptr(mut c))
  ys[2] = Option(ptr(mut N)).Some(ptr(mut b))
  if sum3(ys) != 42 { return 106 }
  ys[2] = Option.None
  if sum3(ys) != 2 { return 107 }
  put(ys, 1, ptr(mut b))
  if sum3(ys) != 42 { return 108 }
  ## a typed-head literal without an annotation
  zs := [Option(ptr(mut N)).None, Option(ptr(mut N)).Some(ptr(mut b))]
  z : Option(ptr(mut N)) = zs[1]
  if val(z) != 40 { return 109 }
  ## an array field: the literal, an element store, the field after it untouched
  mut t := T(n = 1, b = [Option.None, Option.Some(ptr(mut b))], m = 2)
  t0 : Option(ptr(mut N)) = t.b[0]
  if val(t0) != 0 { return 110 }
  t.b[0] = Option.Some(ptr(mut c))
  t1 : Option(ptr(mut N)) = t.b[0]
  t2 : Option(ptr(mut N)) = t.b[1]
  if val(t1) + val(t2) != 42 or t.m != 2 or t.n != 1 { return 111 }
  ## hash buckets: push each node onto its bucket's list
  mut ns := [N(v = 1, next = Option.None), N(v = 2, next = Option.None), N(v = 3, next = Option.None), N(v = 4, next = Option.None), N(v = 32, next = Option.None)]
  mut bk : [Option(ptr(mut N)); 2] = [Option.None, Option.None]
  mut i : usize = 0
  while i < 5 {
    h : usize = i % 2
    nd : ptr(mut N) = ptr(mut ns[i])
    deref(nd).next = bk[h]
    bk[h] = Option.Some(nd)
    i = i + 1
  }
  mut w : u64 = 0
  mut k : usize = 0
  while k < 2 {
    mut p : Option(ptr(mut N)) = bk[k]
    loop { match p { Some(q) => { w = w + deref(q).v; p = deref(q).next }; None => { break } } }
    k = k + 1
  }
  w
}
