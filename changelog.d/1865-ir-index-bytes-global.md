- The shared IR now builds two more index forms, each a checked read (#1865; Types §6.4, CG-13). The
  first is `bytes(x)[i]`, byte `i` of the `[u8]` view of a `str` (Stdlib appendix §3.6). It indexes
  `x`'s own `{ptr, len}` pair, checks `i` against its runtime length, and adds no code-point guard,
  because that guard belongs to a `str` index. The second is a runtime index into a module-global word
  array, `G[i]` with `[usize; N]` or `[i64; N]`. It checks `i` against `N`, then loads the 8-byte cell
  at `addr @G`. aarch64, riscv64 and wasm select `G[i]` from the IR. On x86_64 it stays with the
  legacy emitter, because the selector addresses only a scalar global cell, as it already did for a
  literal index. The compiler's own `src/` builds 103 more functions through the IR (2947 to 3050).
