main := fn() -> usize {
  mut x : usize = 10759
  hx := unchecked bitcast(usize, ptr(x))
  usize(a__b::mm(hx))
}
## Compiled alone (the corpus walk), this file names a module `a__b` it does not have.
## expect: reject
