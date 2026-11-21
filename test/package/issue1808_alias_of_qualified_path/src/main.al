A := m::k::C
main := fn() -> usize {
  mut x : usize = 10759
  hx := unchecked bitcast(usize, ptr(x))
  usize(m::mm(hx) / 256 + m::rd(A, hx) / 256 - 42)
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
