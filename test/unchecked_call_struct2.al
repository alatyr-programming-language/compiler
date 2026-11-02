## #1139 — a 2-word struct returned by a call under the expression grant `unchecked mk(41)`.
## Expected exit 42 (the parent compiler exited 0).
S := struct { a : u64, b : u64 }
mk := fn(n : u64) -> S { S(a = 1, b = n) }
main := fn() -> u64 {
  s := unchecked mk(41)
  s.a + s.b
}
## expect: run 42
