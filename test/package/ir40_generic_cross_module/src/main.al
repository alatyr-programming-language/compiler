## The root's own generic `at` reads the handle's own word.
at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
## Built from the shared IR: the bare `at` is the root's, `m::pick` is `m`'s.
own := fn(h : usize) -> u64 {
  p : ptr(u64) = at(u64, h)
  deref(p)
}
theirs := fn(h : usize) -> u64 { m::mown(h) }
chosen := fn(x : u64, y : u64) -> u64 { m::pick(u64, x, y) }
## The same calls from the legacy emitter.
lboth := fn(h : usize) -> u64 {
  z : f64 = 1.0
  p : ptr(u64) = at(u64, h)
  deref(p) + m::mown(h) + m::pick(u64, 99, 12)
}
main := fn() -> u64 {
  cells : [u64; 2] = [10, 20]
  h := unchecked bitcast(usize, ptr(cells))
  ir := own(h) + theirs(h) + chosen(99, 12)
  if ir != lboth(h) { return 1 }
  ir
}
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
