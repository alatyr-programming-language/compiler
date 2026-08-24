## The WORD-tier twin of `reject_standard_byte_nested_field_addr.al`, and the evidence that the
## nested-field-address hole was never about the byte tier. `Outer` here is an ordinary word-layout
## struct that no part of P1-CLAYOUT touches, and the address of a nested field still reduced to the
## constant 0, so two distinct fields compared EQUAL.
##
## MEASURED, where 42 means the two addresses differ and 7 means they compared equal
## (x86_64 / aarch64 / riscv64 / wasm):
##   base 9e0f397                 7 / trap / trap / trap   <- pre-existing, nothing to do with bytes
##   S3(a) first attempt 4f0c3cb  7 / trap / trap / trap
##   this commit             reject / trap / trap / trap
Inner := struct { x : u64, y : u64 }
Outer := struct { pad : u64, inner : Inner }
main := fn() -> u64 {
  mut o := Outer(pad = 1, inner = Inner(x = 20, y = 22))
  px := ptr(o.inner.x)
  py := ptr(o.inner.y)
  if px == py { return 7 }
  42
}
