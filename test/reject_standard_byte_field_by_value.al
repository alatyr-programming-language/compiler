## CLAYOUT S3(a) — an AGGREGATE FIELD of a standard-byte-layout struct cannot be handed to a call,
## or returned, by value yet. Both by-value addressing forms are word-model (`field_base_ref`'s word
## index and `field_slot`), so the callee receives a block that starts at the wrong place; the same
## two forms serve the aggregate-field RETURN paths, which is why the fence sits in the shared
## resolver rather than in one call site.
##
## MEASURED, this program's exit code — 42 is correct, 1 means `getx(o.inner)` did not return 20
## (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime):
##   base 9e0f397                reject / trap / trap / trap  (its construction fence stops all four)
##   S3(a) first attempt 4f0c3cb       1 / trap / trap /   42   <- wasm was right, x86_64 was not
##   this commit                  reject / trap / trap /   42
## wasm is unchanged and still correct: this fence lives in the x86_64 emitter, which is where the
## wrong value was. The two register-ISA backends trap on passing any struct by value at all.
## The supported spelling is to bind the inner value first — `c := o.inner` IS byte-aware, and
## `standard_byte_aggregate_field.al` locks it at 42 on all four backends. The WORD-layout control
## (`word_layout_struct_by_value_control.al`) passes the same shape by value and returns 42.
Inner := struct { x : u64, y : u64 }
Outer := struct { data : [u8; 4], inner : Inner }
getx := fn(i : Inner) -> u64 { i.x }
main := fn() -> u64 {
  o := Outer(data = [1, 2, 3, 4], inner = Inner(x = 20, y = 22))
  if getx(o.inner) != 20 { return 1 }
  42
}
