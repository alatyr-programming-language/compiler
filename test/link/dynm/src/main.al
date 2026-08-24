## The entry module for the MOD-9 dynamic-link e2e. `sqrt` is resolved from libm at link time
## (`-lm`, dynamic). sqrt(1764.0) = 42.0; `u64(...)` truncates the double to the exit code 42.
sqrt := @extern @abi(c) fn(x : f64) -> f64

main := fn() -> u64 {
  return u64(sqrt(1764.0))
}
