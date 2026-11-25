## e2e — Grammar §2.6 continuing tokens (SYN-12, spec 1.12.0; #1910). `[` is not a continuing token (an
## array literal can begin a statement), so `v : [u64; 3] = xs` followed by a line `[0]` is two
## statements: `v` is the whole array and `[0]` an array literal of its own. The parser used to read the
## two lines as `v : [u64; 3] = xs[0]` and answer 41. A `[` line always begins an array-literal
## statement, which aarch64, riscv64 and wasm stub fail-loud (#1191), so this probe is its own fixture.
main := fn() -> u64 {
  xs : [u64; 3] = [7, 8, 9]
  v : [u64; 3] = xs
  [0]
  v[1] + 34
}
## expect: run 42
