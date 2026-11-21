- **A whole fixed array copied out of a pointer is the whole array (#1809).** On x86_64,
  `v : [u64; 2] = deref(p)` moved one word and left the rest of `v` as whatever the frame held, so
  `v[1]` changed from run to run, and `v.len` was 0. The reassignment `v = deref(p)` of a local
  declared `[T; N]` moved one word too. Memory §4.3 makes `deref(p)` load the whole place, and
  Types §6.4 makes a `[T; N]` value its `N` elements, so both forms now copy every element, for a
  byte or word integer element. Any other element type (a struct, `u16`, `u32`) is refused at the
  assignment with its source line, rather than moving one word. A zero-length `[T; 0]` copies
  nothing (Types §6.5). A length written as a named constant or a constant expression
  (`[u64; K]`, `[u64; 1 + 1]`) is refused, located, until the copy evaluates it (#1833).
  aarch64, riscv64 and wasm refuse both forms, at any length, until they copy them (#1811).
