## e2e — #1723: an enum whose variant carries a niche-folded `Option(ptr(T))` component, on the shared
## IR. Such a component is ONE pointer word in its payload slot (Types §6.2): `None` is the null word and
## `Some(p)` is `p`. A variant of two or more components gives each its own word, so the builder lays
## the enum out like any other. A match binding over the component is an `Option` value of its own,
## which can be matched again. That is the shape of the compiler's own `match deref(e)` over `Expr`.
##   * `walk` and `count` read a list through `match deref(p)` and re-match the bound `Option` (IR);
##   * `mk` builds a node with an `Option` component from a parameter and from a literal (IR);
##   * `lg_mk` and `lg_walk` hold a float local, so the builder refuses them and they stay
##     LEGACY-emitted: a node built by one emitter is read by the other, in both directions.
## Each check answers its own code when it fails; 42 when all held.
L := enum { Nil, Cons(u64, Option(ptr(L))) }

walk := fn(p : ptr(L)) -> u64 {
  match deref(p) {
    L.Nil => { return 0 }
    L.Cons(v, nx) => {
      match nx { Some(q) => { return v + walk(q) }; None => { return v } }
    }
  }
}
count := fn(p : ptr(L)) -> u64 {
  match deref(p) {
    L.Nil => { return 0 }
    L.Cons(v, nx) => {
      match nx { Some(q) => { return 1 + count(q) }; None => { return 1 } }
    }
  }
}
mk := fn(v : u64, nx : Option(ptr(L))) -> L { L.Cons(v, nx) }
mk_last := fn(v : u64) -> L { L.Cons(v, Option(ptr(L)).None) }
lg_mk := fn(v : u64, q : ptr(L)) -> L {
  w := 1.5
  L.Cons(v, Option(ptr(L)).Some(q))
}
lg_walk := fn(p : ptr(L)) -> u64 {
  w := 2.5
  match deref(p) {
    L.Nil => { return 0 }
    L.Cons(v, nx) => {
      match nx { Some(q) => { return v + lg_walk(q) }; None => { return v } }
    }
  }
}

main := fn() -> u64 {
  n3 := mk_last(5)
  n2 := lg_mk(7, ptr(n3))
  n1 := mk(11, Option(ptr(L)).Some(ptr(n2)))
  if walk(ptr(n3)) != 5 { return 1 }
  if walk(ptr(n2)) != 12 { return 2 }
  if walk(ptr(n1)) != 23 { return 3 }
  if count(ptr(n1)) != 3 { return 4 }
  if lg_walk(ptr(n1)) != 23 { return 5 }
  e := L.Nil
  if walk(ptr(e)) != 0 or count(ptr(e)) != 0 { return 6 }
  return walk(ptr(n1)) + walk(ptr(n2)) + 7
}
## expect: run 42
