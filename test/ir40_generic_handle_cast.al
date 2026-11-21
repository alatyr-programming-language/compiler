## IR-40 (#1786): a function the shared IR builds calls a generic function's instance, here the
## handle-cast shape the compiler's own `decl_at` has: `at(T, h)` turns a handle into a `ptr(T)`.
## `rd` and `wr` are built from the shared IR; their call names the instance `at(u64)` that the legacy
## emitter defines, by the label its definition carries (`emit_generic_label`). `lrd` holds a float
## local, which keeps it on the legacy emitter, and calls the SAME instance: one definition, two kinds of
## caller. A second definition under that label would not assemble; a call to a label nobody defines
## would not link; a call to the wrong instance reads the wrong word.
at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
rd := fn(h : usize) -> u64 {
  p : ptr(u64) = at(u64, h)
  deref(p)
}
wr := fn(h : usize, v : u64) {
  p : ptr(mut u64) = at(u64, h)
  deref(p) = v
}
lrd := fn(h : usize) -> u64 {
  z : f64 = 1.0
  p : ptr(u64) = at(u64, h)
  deref(p)
}
main := fn() -> u64 {
  mut cell : u64 = 7
  h := unchecked bitcast(usize, ptr(cell))
  if rd(h) != 7 { return 1 }
  wr(h, 40)
  if lrd(h) != 40 { return 2 }
  if cell != 40 { return 3 }
  rd(h) + 2
}
## expect: run 42
