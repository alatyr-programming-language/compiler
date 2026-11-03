## e2e (#422) — the OUT-OF-VIEW index into a PACKED BYTE range slice used DIRECTLY as an index
## base: `xs[1..3][2]` with `xs : [u8; 4]`. The view is {42, 93}, so index 2 is past its end and
## the built-in bounds guard of Types §6.4 / I11 TRAPS rather than reading `xs[3]` = 55 out of the
## base array: the bound is the view's OWN runtime length `hi - lo`, which is exactly what the bound
## spelling `v := xs[1..3]; v[2]` does and what `arr_slice_direct_index_oob` already pins for a
## one-word `[u64; N]` element.
##
## Measured on `main` `c00eae90` with the published seed 0.2.21 on native x86_64 (`omen`), each
## program built with `alatyr -o <bin> <src>` and the produced binary's own `$?` read outside any
## pipeline: x86_64 never got that far — the build was REFUSED with the located
## `index BASE is not a named array/slice place` refusal, so this row is the regression on x86_64,
## where the trap status (SIGILL 132) replaces a compile-time refusal. aarch64 and riscv64 answered
## 133 (`brk` → SIGTRAP) and WAT 134 (wasmtime's `unreachable`) on the parent, because those three
## store `[u8; N]` as one WORD per element (measured in the emitted GAS: `str x0, [x29, #16]` …
## `#40`) and their direct byte index, bounds check included, already worked: those rows are
## CONTROLS that this change does not move them.
##
## The IN-VIEW half of the same address math — index 2 under `unchecked` answering 55, not trapping
## — is asserted as a value in `issue422_direct_range_slice_byte_index`, so the two fixtures together
## pin that the check is present in checked code and dropped under `unchecked` (CG-7) with the
## address unchanged either way.
main := fn() -> u64 {
  xs : [u8; 4] = [71, 42, 93, 55]
  xs[1..3][2]
}
## expect: trap
