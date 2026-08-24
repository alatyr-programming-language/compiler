## §8.1 — a failing predicate in the UFCS contract surface traps at `T(v)`.
is_nonzero := fn(v : u32) -> bool { return v != 0 }
NonZero := u32.require(is_nonzero)

main := fn() -> u64 {
  x := NonZero(0)
  return 42
}
