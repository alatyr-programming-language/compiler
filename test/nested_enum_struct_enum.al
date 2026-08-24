## Regression: deep nesting — enum whose payload is a struct that has an enum field.
Inner := enum { A, B(u64) }
Mid := struct { i : Inner, k : u64 }
Outer := enum { X(Mid), Y }
main := fn() -> u64 {
  o := Outer.X(Mid(i = Inner.B(40), k = 2))
  match o { Outer::X(m) => { return match m.i { Inner::A => { 0 }; Inner::B(v) => { v } } + m.k }; Outer::Y => { return 0 } }
}
