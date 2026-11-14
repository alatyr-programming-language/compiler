## e2e reject — #1632: an element write through an `in` array parameter. Memory §3.1: a binding is
## immutable unless declared `mut`, and the parameter grammar admits no `mut` (Functions §9 `in-param`);
## Memory §3.3/§3.4: a write through an immutable path is ill-formed, checked always. Before #1632 the AST
## kept no direction for an array parameter, sema let every one be written, and the write reached the
## caller's array: MEASURED on the parent (`774ba852`, native x86_64) `check` passed and x86_64 answered
## 72 (12 was due had the write been refused); aarch64 and riscv64 133, wasm 134.
## expect: reject "check: immutable binding" "at line 11"
put := fn(xs : [u64; 3]) -> u64 {
  r := xs[0]
  if r > 100 { return r }
  xs[1] = 30
  xs[1]
}
main := fn() -> u8 {
  mut a : [u64; 3] = [2, 0, 10]
  r := put(a)
  u8(a[1] + r + 12)
}
