## Issue #817 — a struct local declared WITHOUT an initializer (`mut p : P`, then `p = P(..)`) got a
## ONE-word frame slot on aarch64 and riscv64, because the slot was sized from the parser's one-word
## sentinel value. The whole assignment then wrote `p.y` into the NEXT local's slot. Each check below
## has its own exit code, and a local follows `p` in each helper, so the overlap is visible. On the
## parent, aarch64 and riscv64 built this cleanly and exited 2 (the copy `q := p` read `q.y` as `p.x`:
## 80 where 42 was due), while x86_64 and wasm ran it to 42.
P := struct { x : u64, y : u64 }
copied := fn() -> u64 {
  mut p : P
  p = P(x = 40, y = 2)
  q := p
  q.x + q.y
}
copied_back := fn() -> u64 {
  mut p : P
  p = P(x = 30, y = 4)
  q := p
  p = q
  p.x + p.y
}
neighbour := fn() -> u64 {
  mut p : P
  mut z : u64 = 5
  p = P(x = 1, y = 9)
  p.y + z
}
main := fn() -> u64 {
  if copied() != 42 { return 2 }
  if copied_back() != 34 { return 3 }
  if neighbour() != 14 { return 4 }
  42
}
