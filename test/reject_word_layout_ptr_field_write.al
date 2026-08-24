## The WORD-tier twin of `reject_ptr_into_inner_field_write.al`, and the evidence that the dropped
## store was never about the byte tier either. `Outer` here is an ordinary word-layout struct, and the
## store through a pointer into its inner aggregate still vanished on the BASE compiler, because the
## last-resort write place resolved to a negative slot and stored over the saved frame pointer.
##
## MEASURED, where 42 means the store landed and 20 means it was dropped
## (x86_64 / aarch64 / riscv64 / wasm):
##   base 9e0f397                20 / trap / trap / trap   <- pre-existing silent dropped write
##   S3(a) first attempt 4f0c3cb 20 / trap / trap / trap
##   this commit             reject / trap / trap / trap
## NOTE which fence catches it: for a WORD-tier outer, `ptr(mut o.inner)` is not an addressable place
## at all, so the address-of fence fires one line EARLIER than the store fence and the diagnostic is
## the same one `reject_word_layout_nested_field_addr.al` asserts. For the BYTE tier the address IS
## resolvable (+8, verified in-program) and the store fence is the one that fires — that is the
## difference between this fixture and `reject_ptr_into_inner_field_write.al`.
Inner := struct { x : u64, y : u64 }
Outer := struct { pad : u64, inner : Inner }
main := fn() -> u64 {
  mut o := Outer(pad = 1, inner = Inner(x = 20, y = 22))
  p := ptr(mut o.inner)
  deref(p).x = 41
  if o.inner.x != 41 { return 20 }
  42
}
