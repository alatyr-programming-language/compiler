## e2e / issue #1209 — `j := deref(unchecked bitcast(ptr(J), arg))` copies the whole `J`.
##
## `deref(p)` of a `ptr(J)` is the `J` it points to wherever the pointer comes from (Memory,
## `deref`); `unchecked` changes only the verification mode (CG-7). No binding arm knew a bitcast
## root, so `j` bound as one scalar word and `j.q` read a neighbouring slot.
## Expected exit 42. NON-VACUOUS: on the parent 9b9fea98 (x86_64) `j.t` reads garbage, so `- 7`
## traps (132).
J := struct { q : u64, t : u64 }

w := fn(arg : usize) -> u64 {
  j := deref(unchecked bitcast(ptr(J), arg))
  j.q + j.t - 7
}

main := fn() -> u64 {
  j := J(q = 42, t = 7)
  w(unchecked bitcast(usize, ptr(j)))
}
## expect: run 42
