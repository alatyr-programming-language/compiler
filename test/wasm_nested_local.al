## nested local: `step := i + 1` declared inside a while body gets its own WASM slot, resolves to the
## correct index, and interoperates with top-level locals acc/i. sum_step(9) = 1+2+...+9 = 45.
sum_step := fn(n : u64) -> u64 {
  mut acc := 0
  mut i := 0
  while i < n {
    step := i + 1
    acc = acc + step
    i = i + 1
  }
  return acc
}
main := fn() -> u64 { return sum_step(9) }
