## e2e — #1865: `bytes(s)[i]` is checked against the view's runtime `len` (Types §6.4; Stdlib appendix
## §3.5), so `at("abc", 3)` must trap on every backend, before any byte past the view is read. The
## in-range call before it answers normally, so the trap is the index check and not the function.
## expect: trap
at := fn(s : str, i : usize) -> u8 { bytes(s)[i] }

main := fn() -> u64 {
  if at("abc", 2) != 99 { return 1 }
  u64(at("abc", 3))
}
