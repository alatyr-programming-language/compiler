## §8.1 `@require(pred) T` validity contract — a VIOLATING construction TRAPS. `NonZero(0)` fails
## `is_nonzero` (`0 != 0` is false), so the checked predicate traps (`ud2` → SIGILL → exit 132),
## exactly like a narrowing overflow (§4.2 / I11 / CG-8). `return 42` is unreached. x86-only.
is_nonzero := fn(v : u32) -> bool { return v != 0 }

NonZero := @require(is_nonzero) u32

main := fn() -> u64 {
  x := NonZero(0)
  return 42
}
