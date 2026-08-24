## §8 ARRAY-OF-@packed (spec Types §8) — the DEFERRED corner, asserted FAIL-LOUD (build_reject).
## An array whose ELEMENT is a `@packed` struct (`P` = {u8 a, u32 b} = 5 bytes) wants a byte-precise
## element stride of 5 (the C-ABI layout — `arr[i]` at byte 5*i) and byte-precise packed field offsets.
## The array-of-aggregate machinery is WORD-granular (`base - i*estride*8`, `field_word_offset`), so it
## cannot express a 5-byte stride; emitting the word path would SILENTLY MISCOMPILE (`arr[i]` at byte 8i,
## `.b` read from the next element's word). `arr_elem_info` therefore REJECTS a packed struct element —
## the build fails loud (a valid binary with a wrong result is the forbidden silent-miscompile).
## Wired as `build_reject packed_array` (asserts a NON-ZERO build rc), not `run` (it never links).
P := @packed struct { a : u8, b : u32 }

main := fn() -> u64 {
  arr : [P; 3] = [P(a = 1, b = 100), P(a = 2, b = 200), P(a = 3, b = 300)]
  mut s := 0
  s = s + u64(arr[0].a) + u64(arr[0].b)
  s = s + u64(arr[1].a) + u64(arr[1].b)
  s = s + u64(arr[2].a) + u64(arr[2].b)
  if s != 606 { return 1 }
  return 42
}
