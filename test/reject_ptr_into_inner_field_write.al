## CLAYOUT S3(a) — a store through a pointer taken INTO an inner aggregate was silently dropped.
## The pointer's address is right (+8 from the outer's base, verified in-program), but the write place
## resolver cannot see the pointee's type, so it fell through to the last-resort store with a NEGATIVE
## slot: `-(-1 + 1) * 8` is `-0(%rbp)`, which lands on the saved frame pointer. The write vanished and
## the program read back the OLD value.
##
## MEASURED, this program, where 42 means the store landed and 20 means it was dropped
## (x86_64 / aarch64 / riscv64 / wasm):
##   base 9e0f397                reject / trap / trap / trap   (the construction fence hid it)
##   S3(a) first attempt 4f0c3cb     20 / trap / trap / trap   <- the store disappeared
##   this commit                  reject / trap / trap / trap
## Also NOT specific to the byte tier: the same shape over a word-layout
## `struct { pad : u64, inner : Inner }` dropped the store on the BASE compiler too — see
## `reject_word_layout_ptr_field_write.al`. The supported spelling is to write through the outer
## place (`o.inner.x = 41`), which `standard_byte_aggregate_field.al` locks at 42 on all four backends.
Inner := struct { x : u64, y : u64 }
Outer := struct { data : [u8; 4], inner : Inner }
main := fn() -> u64 {
  mut o := Outer(data = [1, 2, 3, 4], inner = Inner(x = 20, y = 22))
  p := ptr(mut o.inner)
  deref(p).x = 41
  if o.inner.x != 41 { return 20 }
  42
}
