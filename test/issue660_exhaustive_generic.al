## Issue #660 — the over-rejection control: the three generic spellings with every variant covered and
## no `_`, plus a generic callee whose result is NOT one of its type parameters (`-> u64`) and a
## call whose type argument is not an enum (`pass(u64, 32)`); all must stay accepted. Each shape adds
## its variant's value (R = 1, G = 2, B = 3): 1 + 3 + 1 (through `val`) + 5 + 32 = 42. `val` is given a
## bound local, not `pass(C, C.R)` directly — that argument form crashes on x86_64 (#719).
C := enum { R, G, B }
id := fn(T : type, p : ptr(mut T)) -> ptr(mut T) { p }
pass := fn(T : type, v : T) -> T { v }
width := fn(T : type, v : T) -> u64 { 5 }
val := fn(c : C) -> u64 { match c { R => { return 1 }; G => { return 2 }; B => { return 3 } } return 0 }
main := fn() -> u64 {
  mut total := 0
  c1 := pass(C, C.R)
  match c1 { R => { total += 1 }; G => { total += 2 }; B => { total += 3 } }
  c2 := pass(C, C.B)
  match c2 { R => { total += 1 }; G => { total += 2 }; B => { total += 3 } }
  c3 := pass(C, C.R)
  total += val(c3)
  total += width(C, C.G)
  n := pass(u64, 32)
  return total + n
}
