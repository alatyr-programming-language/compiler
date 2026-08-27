## Regression for #169: WASM must not silently keep only the first word when a standard-byte
## aggregate element is written through an array index. The non-WASM backends either preserve the
## value or already reject this shape; WASM must now be fail-loud too.

T := struct { a : u8, b : u8 }

main := fn() -> u64 {
  mut arr : [T; 2]
  arr[0] = T(a = 1, b = 2)
  arr[1] = T(a = 4, b = 2)
  u64(arr[1].a) * 10 + u64(arr[1].b)
}
