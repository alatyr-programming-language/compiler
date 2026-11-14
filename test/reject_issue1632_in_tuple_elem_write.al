## e2e reject — #1632: a component write through an `in` TUPLE parameter, which shares the array
## parameter's representation (`ast::param_is_array`). Memory §3.1/§3.4, as for an array: the binding is
## immutable. MEASURED on the parent (`774ba852`, native x86_64): `check` passed and x86_64 answered 70,
## the write landing in the caller's tuple; aarch64 and riscv64 133, wasm 134.
## expect: reject "check: immutable binding" "at line 7"
put := fn(t : (u64, u64)) -> u64 {
  t.0 = 30
  t.0
}
main := fn() -> u8 {
  mut a : (u64, u64) = (2, 10)
  r := put(a)
  u8(a.0 + r + 10)
}
