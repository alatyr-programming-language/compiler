- **An array or tuple parameter keeps its direction, so a write through an `in` one is refused (#1632).**
  The parser recorded `xs : [T; N]`, `in out xs : [T; N]` and `out xs : [T; N]` the same way, so `check`
  accepted `xs[0] = v` through a plain `in` array parameter and the write reached the caller's array.
  An element write through an `in` array or tuple parameter is now `check: immutable binding` at its
  line (Memory §3.4); an `out` / `in out` one still writes the caller's array. A call the shared IR
  builds now passes an `in` array as the address of a caller-owned copy (Functions §4.1), so a write
  the callee makes through an `in out` argument naming the same array does not reach the copy; a call
  the legacy x86_64 lowerer emits still passes the caller's array itself (#1637). An element write
  through an `in out` array parameter is built by the shared IR on every target instead of trapping on
  aarch64, riscv64 and wasm32.
