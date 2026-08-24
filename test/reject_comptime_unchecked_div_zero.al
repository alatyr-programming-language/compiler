## e2e — CT-12, the `unchecked` half: "an operation whose unchecked behaviour is HARDWARE-defined
## rather than *defined* — division by zero and an over-width shift — remains a diagnostic at
## comptime, because the evaluator has no hardware behaviour to reproduce and I11 forbids inventing
## one" (Comptime §2.6). So `unchecked` does NOT license a comptime division by zero.
## Located at the division (line 6).
K : u64 = unchecked (10 / 0)

main := fn() -> i64 {
  return i64(K)
}
