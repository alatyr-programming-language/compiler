main := fn() -> usize {
  mut x : usize = 10759
  hx := unchecked bitcast(usize, ptr(x))
  usize(p::_q::mm(hx))
}
## Compiled alone (the corpus walk), this file names a module `p` it does not have.
## expect: reject
