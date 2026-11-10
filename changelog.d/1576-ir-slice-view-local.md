- **aarch64, riscv64 and wasm run a slice view local taken from a fixed array (#1576, first step).**
  `s : Slice(u64) = xs[1..4]` over a fixed-array local, with literal bounds, then `t := s`, `t.len` and
  `t[i]`, trapped on the three non-x86 backends. The shared IR now
  builds such a view as the two-word `{ptr, len}` pair (Types §7) and checks every index against the
  runtime length. Passing a view to a call, returning one, a runtime bound, and `str` still fall back.
