- A fixed array of struct or enum elements, `[P; N]`, and an aggregate local declared without an
  initializer (`mut p : P`, `mut xs : [P; 2]`) are now built from the shared IR on every backend (#1705):
  one frame object of `N * stride` bytes, the stride the element's size rounded up to its alignment
  (Types §6.4), indices checked like a scalar array's. Programs that aarch64, riscv64 and wasm answered
  with a fail-loud stub, and that x86_64 refused, now run; an uninitialized `[T; N]` no longer writes its
  elements over the x86_64 frame when its function is built from the IR (#1708). Arrays of `@packed` or
  otherwise levered structs keep their refusal.
