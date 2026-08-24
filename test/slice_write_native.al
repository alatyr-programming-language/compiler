## Cross-backend scalar range-slice WRITE: a slice `s := xs[lo..hi]` is a VIEW — `s[i] = v` stores
## through the data pointer into the backing array. Read s[1] (=xs[1]=2), add 40, write back → xs[1]=42.
## Lowered on x86 + aarch64 + riscv64 (wasm has no IndexAssign yet → traps, allowed by the sweep).
main := fn() -> u64 {
  mut xs : [u64; 4] = [1, 2, 3, 4]
  s := xs[0..3]
  s[1] = s[1] + 40
  return xs[1]
}
