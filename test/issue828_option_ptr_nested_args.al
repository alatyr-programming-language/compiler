## e2e / issue #828 — nested calls passing `Option(ptr(T))` values with no frame home.
##
## A folded `Option(ptr(T))` argument that is not a named local (a field read, a call result, an array
## element, a folded global) reaches its by-reference parameter through a staged agg-temp word. Two such
## words live at once — an outer call's while a nested call in its arguments stages its own — once
## overflowed the pool, refusing a valid program. #815's measured pool sizing holds them; this row keeps
## that nesting covered for the folded forms.
##
## 42 means every hand-off held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
H := struct { k : u64, head : Option(ptr(mut N)) }
mut G : Option(ptr(mut N)) = Option.None

val := fn(o : Option(ptr(mut N))) -> u64 { match o { Some(q) => { return deref(q).v }; None => { return 0 } }; 0 }
two := fn(o : Option(ptr(mut N)), w : u64) -> u64 { val(o) + w }
pair := fn(o : Option(ptr(mut N)), p : Option(ptr(mut N))) -> u64 { val(o) + val(p) }
nxt := fn(q : ptr(mut N)) -> Option(ptr(mut N)) { deref(q).next }

main := fn() -> u64 {
  mut c := N(v = 30, next = Option.None)
  mut b := N(v = 10, next = Option.Some(ptr(mut c)))
  mut a := N(v = 2, next = Option.Some(ptr(mut b)))
  h := H(k = 1, head = Option.Some(ptr(mut a)))
  xs : [Option(ptr(mut N)); 2] = [Option.None, Option.Some(ptr(mut b))]
  G = Option.Some(ptr(mut c))
  ## a field read beside a nested call that stages a field read
  if two(h.head, val(a.next)) != 12 { return 100 }
  ## two staged words in one call, one of them a call result
  if pair(nxt(ptr(mut a)), b.next) != 40 { return 101 }
  ## an element and a global, nested three deep
  if two(xs[1], two(G, val(nxt(ptr(mut b))))) != 70 { return 102 }
  pair(h.head, a.next) + pair(xs[0], b.next)
}
