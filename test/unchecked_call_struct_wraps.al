## #1139 — the grant still applies to the call's arguments once the struct binding is fixed:
## `M + 42` wraps to 41 under `unchecked` (CG-7) instead of trapping, and the struct arrives
## whole. Expected exit 42.
S := struct { a : u64, b : u64, c : u64 }
mk := fn(n : u64) -> S { S(a = 1, b = n, c = 0) }
main := fn() -> u64 {
  M : u64 = 18446744073709551615
  s := unchecked mk(M + 42)
  s.a + s.b
}
## expect: run 42
