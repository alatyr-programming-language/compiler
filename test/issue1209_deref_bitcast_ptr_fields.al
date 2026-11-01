## e2e / issue #1209 — the copied struct's POINTER fields are the ones stored (the pipeline pilot's
## thread job). `j := deref(unchecked bitcast(ptr(J), arg))` then `deref(j.q)`.
## Expected exit 42. NON-VACUOUS: on the parent 9b9fea98 (x86_64) it dies with SIGSEGV (139).
J := struct { q : ptr(mut u64), t : ptr(mut u64) }

w := fn(arg : usize) -> u64 {
  j := deref(unchecked bitcast(ptr(J), arg))
  deref(j.q) + deref(j.t) - 7
}

main := fn() -> u64 {
  mut a : u64 = 42
  mut b : u64 = 7
  j := J(q = ptr(mut a), t = ptr(mut b))
  w(unchecked bitcast(usize, ptr(j)))
}
## expect: run 42
