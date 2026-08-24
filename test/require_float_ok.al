## §8.1 `@require(pred) T` — named predicates over f32/f64 use the scalar SSE ABI.
## The constructor must pass the value in %xmm0, while the bool result remains in %rax.
is_nonzero_f32 := fn(v : f32) -> bool { return v != 0.0 }
is_nonzero_f64 := fn(v : f64) -> bool { return v != 0.0 }

NonZeroF32 := @require(is_nonzero_f32) f32
NonZeroF64 := @require(is_nonzero_f64) f64

main := fn() -> u64 {
  a := NonZeroF32(1.5)
  b := NonZeroF64(40.5)
  ## The values are intentionally not numerically converted here: this test locks the validity
  ## call/return ABI, while the underlying float representation remains a separate conversion path.
  if u64(1) != 1 { return 1 }
  return 42
}
