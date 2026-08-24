## CT-12 / Comptime §2.6: resolving a named module constant must not hide a checked guard.
## `MAX` is a valid u64 constant; the later initializer must diagnose `MAX + 1` at this operation,
## rather than build a deferred runtime trap.
MAX : u64 = 18446744073709551615
K : u64 = MAX + 1

main := fn() -> i64 {
  return i64(K)
}
