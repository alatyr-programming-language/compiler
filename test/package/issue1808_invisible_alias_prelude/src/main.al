main := fn() -> u64 {
  mut x : u64 = 10759
  hx := unchecked bitcast(usize, ptr(x))
  m::mm(hx) / 256
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
