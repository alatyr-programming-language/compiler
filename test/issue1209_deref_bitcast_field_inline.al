## e2e / issue #1209 — a field read straight off `deref(unchecked bitcast(ptr(J), arg))`, with no
## binding: `deref(deref(unchecked bitcast(ptr(J), arg)).q)`. The field read reaches the pointee
## through the bitcast, as it does through a pointer-returning call.
## Expected exit 42. NON-VACUOUS: on the parent 9b9fea98 (x86_64) it dies with SIGSEGV (139).
J := struct { q : ptr(mut u64), t : ptr(mut u64) }

w := fn(arg : usize) -> u64 {
  deref(deref(unchecked bitcast(ptr(J), arg)).q) + deref(deref(unchecked bitcast(ptr(J), arg)).t) - 7
}

main := fn() -> u64 {
  mut a : u64 = 42
  mut b : u64 = 7
  j := J(q = ptr(mut a), t = ptr(mut b))
  w(unchecked bitcast(usize, ptr(j)))
}
