## Fail-loud control for #169: a wider byte-layout struct is outside the bounded native ABI slice. The
## x86 byte-layout path remains the semantic control (42); non-x86 boundaries must trap rather than
## carry a partial or differently-laid-out value.

Triple := struct { a : u8, b : u8, c : u8 }

take_triple := fn(s : Triple) -> u64 {
  42
}

main := fn() -> u64 {
  take_triple(Triple(a = 4, b = 2, c = 1))
}
