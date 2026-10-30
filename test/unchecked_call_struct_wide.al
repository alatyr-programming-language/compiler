## #1139 — a struct too wide for the return registers (returned through the hidden result
## pointer) under the grant `unchecked mk(41)`. Expected exit 42.
W := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
mk := fn(n : u64) -> W { W(a = 1, b = 0, c = 0, d = 0, e = 0, f = 0, g = 0, h = 0, i = n) }
main := fn() -> u64 {
  w := unchecked mk(41)
  w.a + w.i
}
