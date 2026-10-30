## #1139 — the block form of the grant, `unchecked { mk(41) }`, around a 3-word struct return.
## Expected exit 42 (the parent compiler exited 0).
S := struct { a : u64, b : u64, c : u64 }
mk := fn(n : u64) -> S { S(a = 1, b = n, c = 0) }
main := fn() -> u64 {
  s := unchecked { mk(41) }
  s.a + s.b
}
