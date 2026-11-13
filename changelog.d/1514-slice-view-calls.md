- **A `Slice(T)` over a narrow array reads the right elements on x86_64 when the shared IR builds both
  ends (#1514).** A range slice of a `[u16; N]`, `[u32; N]`, `[bool; N]` or inferred `[u8; N]` local,
  passed to or returned from a `Slice(T)` parameter or result, iterated with `for` or indexed, read
  the wrong bytes: the array kept one word per element while the reader stepped the element's own
  size. The shared IR now lays the array out at the element's own stride (Types §6.4), so
  `pass(a16[0..3])[2]` and `for x in s` answer the stored values when the IR builds the function that
  cuts the view and every function it reaches. A narrow-element view never crosses between a function
  the IR builds and one it does not: such a call keeps both ends on the previous emitter, which still
  reads some of these views wrong (#1559). aarch64, riscv64 and wasm keep such functions on their
  previous emitter, unchanged.
