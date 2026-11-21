## IR-39 (#1786): a record shaped like the compiler's own (`Decl`, `Param`): narrow scalars, a niche-folded
## `Option(ptr(T))`, a nested struct of pointers and a payload-less enum, copied whole through a pointer
## (`d : D = deref(dp)`). The shared IR reads each child at `lower_layout::field_byte_place`, where
## x86_64's legacy constructor and writers put it. `lgm` (nine arguments) keeps `main` legacy.
lgm := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64) -> u64 { a }
N := struct { v : u64, next : Option(ptr(mut N)) }
P := struct { f : ptr(u64), g : ptr(u64), h : ptr(u64) }
K := enum { X, Y, Z }
D := struct { s : usize, is_fn : bool, kind : u8, head : Option(ptr(mut N)), pr : P, k : K, l : i32 }
sum := fn(dp : ptr(D)) -> u64 {
  d := deref(dp)
  mut acc : u64 = 0
  mut c := d.head
  loop {
    match c {
      Some(q) => { n := deref(q); acc = acc + n.v; c = n.next }
      None => { break }
    }
  }
  if d.is_fn { acc = acc + 100 }
  acc + u64(d.kind) + d.s + u64(0 - d.l)
}
kind := fn(dp : ptr(D)) -> u64 {
  d : D = deref(dp)
  match d.k { K.X => { 1 }; K.Y => { 2 }; K.Z => { 3 } }
}
setk := fn(dp : ptr(mut D), n : ptr(mut N)) {
  mut d : D = deref(dp)
  d.k = K.Z
  d.kind = 9
  d.head = Option(ptr(mut N)).Some(n)
  deref(dp) = d
}
main := fn() -> u64 {
  if lgm(0, 0, 0, 0, 0, 0, 0, 0, 0) != 0 { return 99 }
  mut a : u64 = 1
  mut n2 := N(v = 20, next = Option(ptr(mut N)).None)
  mut n1 := N(v = 10, next = Option(ptr(mut N)).Some(ptr(mut n2)))
  mut d := D(s = 3, is_fn = true, kind = 4, head = Option(ptr(mut N)).Some(ptr(mut n1)), pr = P(f = ptr(a), g = ptr(a), h = ptr(a)), k = K.Y, l = -5)
  if sum(ptr(d)) != 142 { return 1 }
  if kind(ptr(d)) != 2 { return 2 }
  setk(ptr(mut d), ptr(mut n2))
  if d.kind != 9 or d.l != -5 or not d.is_fn { return 3 }
  match d.k { K.Z => {}; K.X => { return 4 }; K.Y => { return 5 } }
  if sum(ptr(d)) != 137 { return 6 }
  if deref(d.pr.g) != 1 { return 7 }
  42
}
## expect: run 42
