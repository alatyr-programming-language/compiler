## P1-CLAYOUT S3(a): a standard byte-layout struct may contain a WORD-GRANULAR aggregate field — one
## whose own §6.1 byte offsets are exactly its word-model offsets times 8, so all four emitters build
## the same image for it. Its nested construction, reads, and writes use the containing struct's byte
## offsets without changing the inner value's words.
##
## MEASURED exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime):
##   base 9e0f397                reject / trap / trap / trap   (the construction fence; 133/133/134)
##   S3(a) first attempt 4f0c3cb     42 /   42 /   42 /   42
##   this commit                     42 /   42 /   42 /   42
## The non-word-granular counterpart is fenced — see `reject_standard_byte_subword_child.al`.

Inner := struct { x : u64, y : u64 }
Outer := struct { data : [u8; 4], inner : Inner }

main := fn() -> u64 {
  mut o := Outer(data = [1, 2, 3, 4], inner = Inner(x = 20, y = 22))
  if o.inner.x != 20 { return 1 }
  if o.inner.y != 22 { return 2 }
  copy := o.inner
  if copy.x != 20 { return 3 }
  if copy.y != 22 { return 4 }
  if o.data[2] != 3 { return 5 }
  o.inner.y = 28
  if o.inner.y != 28 { return 6 }
  o.inner = Inner(x = 41, y = 33)
  if o.inner.x != 41 { return 7 }
  if o.inner.y != 33 { return 8 }
  if o.data[2] != 3 { return 9 }
  42
}
