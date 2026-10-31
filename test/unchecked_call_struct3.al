## #1139 — a 3-word struct returned by a call under the expression grant `unchecked mk(41)`.
## `unchecked` changes only the verification mode (Concurrency §6.2, CG-7); the binding holds
## the same struct as without the grant. Expected exit 42. The parent compiler stored only the
## first return register into a one-word slot and the program exited 0.
S := struct { a : u64, b : u64, c : u64 }
mk := fn(n : u64) -> S { S(a = 1, b = n, c = 0) }
main := fn() -> u64 {
  s := unchecked mk(41)
  s.a + s.b
}
