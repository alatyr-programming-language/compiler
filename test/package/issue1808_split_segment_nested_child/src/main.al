main := fn() -> usize {
  mut x : usize = 10759
  hx := unchecked bitcast(usize, ptr(x))
  usize(m::r::mm(hx))
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
