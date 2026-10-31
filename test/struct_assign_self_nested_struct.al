## #951: a struct literal reassigned to the local it reads, whose FIRST initializer is itself a nested
## struct literal (`I(x = q.inner.y, y = q.inner.x)`). Built in place it reads the `x` it just wrote
## (the legacy twins answered 43, and wasm 21 with the inner zeroed). x86_64 builds it in a temp block
## (#909) and the twins build it from the shared IR (slice 3n), each in its own object, so all four
## answer the literal's value: inner = (2, 1), z = 21 -> 2 * 10 + 1 + 21 = 42.
I := struct { x : i64, y : i64 }
Q := struct { inner : I, z : i64 }
main := fn() -> u64 {
  mut q := Q(inner = I(x = 1, y = 2), z = 3)
  q = Q(inner = I(x = q.inner.y, y = q.inner.x), z = 21)
  u64(q.inner.x * 10 + q.inner.y + q.z)
}
## expect: run 42
