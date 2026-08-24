## CLAYOUT S3(a) — a standard-byte-layout struct cannot cross a call boundary by value yet. The
## by-reference struct-parameter ABI resolves the callee's field reads with the WORD model, so a
## `[u8; 4]` field counts as FOUR words there while it occupies four BYTES: every field read in the
## callee lands at the wrong offset. The byte-precise parameter/return ABI is audit stage S3(e).
##
## MEASURED, this program's exit code — 42 is correct, 1 means `readx(o)` did not return 20
## (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime):
##   base 9e0f397                reject / trap / trap / trap   (exit 133 / 133 / 134)
##   S3(a) first attempt 4f0c3cb       1 / trap / trap / trap   <- the callee emitted `movq 32(%rax)`,
##                                                                 word 4, and read 0 instead of 20
##   this commit                  reject / trap / trap / trap
## The WORD-layout control is `word_layout_struct_by_value_control.al`: the identical shape over
## `struct { pad : u64, inner : Inner }` returns 42 on x86_64, so this fence is the byte tier's, not a
## general limit on passing a struct by value.
Inner := struct { x : u64, y : u64 }
Outer := struct { data : [u8; 4], inner : Inner }
readx := fn(o : Outer) -> u64 { o.inner.x }
main := fn() -> u64 {
  o := Outer(data = [1, 2, 3, 4], inner = Inner(x = 20, y = 22))
  if readx(o) != 20 { return 1 }
  42
}
