## P1-CLAYOUT S3(a) — taking the address of a NESTED field reduced to the constant 0, so two distinct
## fields reported one and the same address. An address is never a safe placeholder: `px == py` then
## answers "the same field", and any store through such a pointer writes to page zero.
##
## MEASURED, this program, where 42 means the two addresses differ and 7 means they compared EQUAL
## (x86_64 / aarch64 / riscv64 / wasm):
##   base 9e0f397                reject / trap / trap / trap   (the construction fence hid it)
##   S3(a) first attempt 4f0c3cb      7 / trap / trap / trap   <- two fields, one address
##   this commit                  reject / trap / trap / trap
## The defect is NOT specific to the byte tier: the same probe over an ordinary word-layout
## `struct { pad : u64, inner : Inner }` also answered 7 on the BASE compiler — see
## `reject_word_layout_nested_field_addr.al`. Only two corpus fixtures take a field address at all
## (`atomic_global_field`, a global; `standard_byte_array_field`, a byte-layout local's own scalar
## field), and both keep working, so this closes a hole instead of narrowing support.
Inner := struct { x : u64, y : u64 }
Outer := struct { data : [u8; 4], inner : Inner }
main := fn() -> u64 {
  mut o := Outer(data = [1, 2, 3, 4], inner = Inner(x = 20, y = 22))
  px := ptr(o.inner.x)
  py := ptr(o.inner.y)
  if px == py { return 7 }
  42
}
