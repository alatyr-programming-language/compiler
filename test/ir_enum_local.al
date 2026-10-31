## IR slice 4a (`docs/ir-slice-4.md`): enum locals are frame objects in the shared layout (tag word,
## then one word per payload component), built from the shared IR on every twin: a pinned discriminant
## (`Code.B` is 10), variants with zero, one and two components and a reassignment, a generic instance
## typed by its annotation. Each arm binds its payload by loading its component.
## 3 + 25 + 7 + 12 - 25 + 5 + 15 = 42.
Code := enum { A = 5, B = 10, C = 100 }
Sh := enum { Pt, Sq(u64), Rect(u64, i64) }
area := fn(k : u64) -> u64 {
  mut s := Sh.Rect(6, 0 - 2)
  if k == 0 { s = Sh.Sq(5) }
  if k == 1 { s = Sh.Pt }
  match s {
    Sh.Pt => { return 7 }
    Sh.Sq(w) => { return w * w }
    Sh.Rect(w, h) => { return w * u64(0 - h) }
  }
}
main := fn() -> u64 {
  x := Code.B
  mut r : u64 = 0
  match x {
    Code.A => { r = 1 }
    Code.B => { r = 3 }
    Code.C => { r = 2 }
  }
  o : Option(u64) = Option.Some(5)
  t : u64 = match o { Some(v) => v ; None => 0 }
  r + area(0) + area(1) + area(2) - 25 + t + 15
}
## expect: run 42
