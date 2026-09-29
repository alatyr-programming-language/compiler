## Issue #660 / Control Flow §5.1 — the same generic `-> ptr(mut T)` call inlined into the scrutinee,
## `match deref(id(C, …))`. Accepted by the parent with `B` uncovered and no `_`; refused now.
C := enum { R, G, B }
id := fn(T : type, p : ptr(mut T)) -> ptr(mut T) { p }
main := fn() -> u64 {
  mut c := C.R
  match deref(id(C, ptr(mut c))) { R => { return 42 }; G => { return 1 } }
  return 2
}
