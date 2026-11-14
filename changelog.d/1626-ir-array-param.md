- **The shared IR builds fixed-array parameters, and copies an array field (#1626).** A function with an
  `xs : [T; N]` parameter of 8-byte elements, a call to one, and an array copy from such a parameter or
  from a struct's array field (`ys : [u64; 3] = s.arr`) are now built from the IR; before, the builder
  refused them and every backend kept a legacy emitter that answered a wrong value (x86_64 trapped or
  answered 17 where 42 was due, aarch64 224 and 5) or trapped. The array is passed as its address, the
  convention every legacy emitter uses; Functions §4.1's copy for an `in` array is not made yet (#1632).
