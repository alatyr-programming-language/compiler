## IR slice 3c (`docs/ir-slice-3.md` §7): an index of a fixed array local is CHECKED — `bound i, N`
## traps before any address is formed (Types §6.4; I11). `pick(3)` on a `[u64; 3]` must trap on every
## backend: x86_64 `ud2` (SIGILL, 132), aarch64 `brk` / riscv64 `ebreak` (SIGTRAP, 133). The in-range
## call before it answers normally, so the trap is the index check and not the function. The legacy
## emitters trap too: this guards the IR's `bound` (and its omission being wrong) on the twins.
pick := fn(i : usize) -> u64 {
  xs : [u64; 3] = [40, 41, 42]
  xs[i]
}
main := fn() -> u64 {
  ok := pick(2)
  if ok != 42 { return 1 }
  pick(3)
}
