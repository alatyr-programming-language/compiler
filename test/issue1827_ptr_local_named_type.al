## Issue #1827 — a pointer local whose annotation NAMES its pointer type rather than spelling it:
## `q : T = deref(p)` inside a generic at `T = ptr(Node)`, and `q : P = deref(p)` with `P := ptr(Node)`.
## Memory §4.3: `deref(q)` designates the place `q` points to, and a field projection of that place reads
## the field; Declarations §1.3 makes `P` the type `ptr(Node)`, and a generic instance's `T` is its
## argument. x86_64 read the pointee off the annotation's spelling, found no `ptr(…)` there, bound `q`
## as a scalar, and lowered `deref(q).b` to the constant 0 on both the IR-selected and the legacy path
## (the IR builder declines both functions). The twins trap on the address-of stub (#1188).
## Due 42: 40 from the generic instance's `.b`, 2 from the alias's `.a`.
## spec: Memory §4.3; Declarations §1.3
Node := struct { b : u64, a : u64 }
P := ptr(Node)
by_param := fn(T : type, h : usize) -> u64 {
  p : ptr(T) = unchecked bitcast(ptr(T), h)
  q : T = deref(p)
  deref(q).b
}
by_alias := fn(h : usize) -> u64 {
  p : ptr(P) = unchecked bitcast(ptr(P), h)
  q : P = deref(p)
  deref(q).a
}
main := fn() -> u64 {
  mut t : Node = Node(b = 40, a = 2)
  mut pt : ptr(Node) = ptr(t)
  h := unchecked bitcast(usize, ptr(pt))
  by_param(ptr(Node), h) + by_alias(h)
}
## expect: run 42
