## Issue #557 / Control Flow §5.1 — the second OVER-REJECTION control: §5.1 makes a `_` default
## exhaustive by construction ("every variant … is covered, or a `_` default is present"), so a
## `match` that covers ONE variant and defaults the rest must still be ACCEPTED in every one of the
## six scrutinee spellings. Each shape answers 7, and 6 * 7 = 42.
C := enum { R, G, B }
H := struct { t : C }
w_param := fn(c : C) -> u64 { match c { R => { return 7 }; _ => { return 0 } } return 0 }
w_deref := fn(q : ptr(C)) -> u64 { match deref(q) { R => { return 7 }; _ => { return 0 } } return 0 }
w_call_src := fn() -> C { return C.R }
main := fn() -> u64 {
  mut total := 0
  total += w_param(C.R)
  a : C = C.R
  match a { R => { total += 7 }; _ => {} }
  b := C.R
  match b { R => { total += 7 }; _ => {} }
  mut d := C.R
  total += w_deref(ptr(mut d))
  h := H(t = C.R)
  match h.t { R => { total += 7 }; _ => {} }
  match w_call_src() { R => { total += 7 }; _ => {} }
  return total
}
