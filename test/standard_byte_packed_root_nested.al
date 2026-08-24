## P1-CLAYOUT S3(a) — `@packed` is its OWN tier, not the standard byte tier, even when the packed
## struct happens to carry a byte array. The layout oracle (`layout_kind`) decides PACKED before BYTE
## for exactly this reason: a resolver that asks only "does this struct have a direct byte array
## field?" answers yes for a packed struct too, steals the root from the packed emitter, and reads the
## nested field at §6.1 offsets instead of the packed byte cursor.
##
## MEASURED, this program, exit code (x86_64 native / aarch64 qemu / riscv64 qemu / wasm wasmtime):
##   base 9e0f397                42 / 42 / 42 / 42   (correct everywhere)
##   S3(a) first attempt 4f0c3cb 42 /  1 /  1 /  1   (o.inner.x read as data[1] = 2, so step 1 failed)
##   this commit                 42 / 42 / 42 / 42
## The three cross backends were the ones that regressed: their nested-field resolvers gated on the
## bare byte-array predicate. x86_64 was unaffected only because its own packed read arm ran first.
Inner := struct { x : u64, y : u64 }
Outer := @packed struct { data : [u8; 8], inner : Inner }
main := fn() -> u64 {
  mut o := Outer(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Inner(x = 20, y = 22))
  if o.inner.x != 20 { return 1 }
  if o.inner.y != 22 { return 2 }
  if o.data[1] != 2 { return 3 }
  if o.data[7] != 8 { return 4 }
  42
}
