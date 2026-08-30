## Issue #254: an enum array stored in a struct field must preserve the selected
## element's discriminant and payload when it is matched or passed to a callee.
## The controls exercise the already-supported local-array, plain-enum-field,
## array-of-struct-enum-field, and pointer-to-plain-enum shapes. Mutable-global
## struct-field arrays are covered too; pointer-derived and packed/byte-layout
## roots remain explicit fail-loud residuals.
E := enum { A(u64), B(u64), Empty }
N := enum { Zero, One, Two }
P := struct { x : u64, y : u64 }
Q := struct { x : u64 }
Holder := struct { marker : u64, items : [E; 3], tags : [N; 3], words : [P; 2], singles : [Q; 2], plain : E }
Elem := struct { e : E }
mut global_holder := Holder(marker = 99, items = [E.A(7), E.B(5), E.Empty], tags = [N.Zero, N.One, N.Two], words = [P(x = 1, y = 2), P(x = 3, y = 4)], singles = [Q(x = 5), Q(x = 2)], plain = E.B(4))

take := fn(e : E) -> u64 {
  match e {
    E::A(v) => { return v }
    E::B(v) => { return v + 1 }
    E::Empty => { return 0 }
  }
}

take_p := fn(p : P) -> u64 { return p.x + p.y }
take_q := fn(q : Q) -> u64 { return q.x }

take_with_prefix := fn(k : u64, e : E) -> u64 {
  return k + take(e)
}

read_items := fn(s : Holder) -> u64 {
  mut total : u64 = 0
  match s.items[0] {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => { total = total + 30 }
  }
  match s.items[1] {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => { total = total + 30 }
  }
  match s.items[2] {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => { total = total + 30 }
  }
  return total
}

read_tags := fn(s : Holder) -> u64 {
  mut total : u64 = 0
  match s.tags[0] {
    N::Zero => { total = total + 1 }
    N::One => { total = total + 2 }
    N::Two => { total = total + 3 }
  }
  match s.tags[1] {
    N::Zero => { total = total + 1 }
    N::One => { total = total + 2 }
    N::Two => { total = total + 3 }
  }
  match s.tags[2] {
    N::Zero => { total = total + 1 }
    N::One => { total = total + 2 }
    N::Two => { total = total + 3 }
  }
  return total
}

call_items := fn(s : Holder) -> u64 {
  mut total : u64 = 0
  total = total + take(s.items[0])
  mut i := 1
  total = total + take(s.items[i])
  total = total + take(s.items[2])
  total = total + take_with_prefix(10, s.items[i])
  return total
}

field_args := fn(s : Holder) -> u64 {
  mut total : u64 = 0
  mut i := 1
  total = total + take_p(s.words[i])
  total = total + take_q(s.singles[0])
  total = total + take_with_prefix(20, s.items[i])
  return total
}

global_match := fn() -> u64 {
  mut total : u64 = 0
  match global_holder.items[0] {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => { total = total + 30 }
  }
  match global_holder.items[1] {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => { total = total + 30 }
  }
  match global_holder.items[2] {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => { total = total + 30 }
  }
  return total
}

global_args := fn() -> u64 {
  mut total : u64 = 0
  mut i := 1
  total = total + take(global_holder.items[0])
  total = total + take(global_holder.items[i])
  total = total + take_p(global_holder.words[i])
  total = total + take_q(global_holder.singles[0])
  return total
}

read_ptr := fn(p : ptr(mut E)) -> u64 {
  match deref(p) {
    E::A(v) => { return v }
    E::B(v) => { return v + 1 }
    E::Empty => { return 0 }
  }
}

controls := fn(s : Holder) -> u64 {
  local := [E.A(5), E.B(8), E.Empty]
  mut total : u64 = 0
  match local[0] {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => {}
  }
  match s.plain {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => {}
  }
  elems := [Elem(e = E.A(2)), Elem(e = E.Empty)]
  match elems[0].e {
    E::A(v) => { total = total + v }
    E::B(v) => { total = total + v }
    E::Empty => {}
  }
  mut e := E.A(1)
  total = total + read_ptr(ptr(e))
  return total
}

main := fn() -> u64 {
  s := Holder(marker = 99, items = [E.A(7), E.B(5), E.Empty], tags = [N.Zero, N.One, N.Two], words = [P(x = 1, y = 2), P(x = 3, y = 4)], singles = [Q(x = 5), Q(x = 2)], plain = E.B(4))
  if read_items(s) != 42 { return 1 }
  if read_tags(s) != 6 { return 2 }
  if call_items(s) != 29 { return 3 }
  if field_args(s) != 38 { return 4 }
  if controls(s) != 12 { return 5 }
  if global_match() != 42 { return 6 }
  if global_args() != 25 { return 7 }
  return 42
}
