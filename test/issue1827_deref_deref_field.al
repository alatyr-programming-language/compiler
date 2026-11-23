## e2e / issue #1827 — `deref(deref(p)).f` through a pointer-to-pointer reads the field.
##
## Memory §4.3: `deref(p)` designates the place `p` points to, and a field projection of that place reads
## the field. Covered: the issue's own shape (a `ptr(ptr(Node))` parameter, field `.b`), the same at field
## `.a`, `p` bound from an `unchecked bitcast` of a word, and the inner pointer bound first
## (`q := deref(p); deref(q).b`). Each check owns a code from 11 up; 42 means every field arrived.
## `test/issue1827_deref_deref_param.al` is the issue's program verbatim.
##
## NOT covered here (still open on #1827): a GENERIC at `T = ptr(Node)` that binds `q : T = deref(p)`
## and reads `deref(q).b` answers 0 at `dc9e18e2` on both x86_64 paths.
##
## NON-VACUOUS: on the Stage1 of `a5fc9766` and the 0.6.0 seed (omen, x86_64) every row answered 0: the
## legacy emitter lowered the read as `movq $0, %rax`. At `dc9e18e2` the default x86_64 path (the IR
## selector) answers 42; `x86-legacy` still answers 11.
Node := struct { a : u64, b : u64 }

rd := fn(p : ptr(ptr(Node))) -> u64 { deref(deref(p)).b }
rda := fn(p : ptr(ptr(Node))) -> u64 { deref(deref(p)).a }

rdc := fn(h : usize) -> u64 {
  p : ptr(ptr(Node)) = unchecked bitcast(ptr(ptr(Node)), h)
  deref(deref(p)).b
}

rdq := fn(h : usize) -> u64 {
  p : ptr(ptr(Node)) = unchecked bitcast(ptr(ptr(Node)), h)
  q := deref(p)
  deref(q).b
}

main := fn() -> u64 {
  mut u : Node = Node(a = 1, b = 42)
  mut pu : ptr(Node) = ptr(u)
  if rd(ptr(pu)) != 42 { return 11 }
  if rda(ptr(pu)) != 1 { return 12 }
  h := unchecked bitcast(usize, ptr(pu))
  if rdc(h) != 42 { return 13 }
  if rdq(h) != 42 { return 14 }
  42
}
## expect: run 42
