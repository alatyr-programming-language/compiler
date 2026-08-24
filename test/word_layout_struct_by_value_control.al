## P1-CLAYOUT S3(a) CONTROL — the by-value fences added for the standard BYTE tier must not touch the
## ordinary WORD tier. This is the same program shape as `reject_standard_byte_param.al` and
## `reject_standard_byte_field_by_value.al` with the byte array replaced by a plain `u64`, so the only
## difference is which layout tier the outer struct is in.
##
## MEASURED (x86_64 / aarch64 / riscv64 / wasm):
##   base 9e0f397                42 / trap / trap / trap
##   S3(a) first attempt 4f0c3cb 42 / trap / trap / trap
##   this commit                 42 / trap / trap / trap
## The cross-backend traps are pre-existing and identical on all three compilers: those backends do
## not implement passing a struct by value at all, which is why the byte-tier siblings above trap
## there too rather than because of anything this slice does.
Inner := struct { x : u64, y : u64 }
Outer := struct { pad : u64, inner : Inner }
readx := fn(o : Outer) -> u64 { o.inner.x }
getx := fn(i : Inner) -> u64 { i.x }
main := fn() -> u64 {
  o := Outer(pad = 1, inner = Inner(x = 20, y = 22))
  if readx(o) != 20 { return 1 }
  if getx(o.inner) != 20 { return 2 }
  if o.inner.y != 22 { return 3 }
  if o.pad != 1 { return 4 }
  42
}
