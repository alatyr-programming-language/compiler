## Issue #429 (Types §7 · Stdlib appendix §3.6 · Memory §3.3) — an indexed write into a `str`
## bound with `:=`. The target IS a place by Grammar §3.3 (`s` is an identifier, `s[i]` a legal
## place), so the parser fence added for #411 never sees it and the parse is correct; what was
## missing was the permission check. `str` is the slice `[u8]`, whose element permission comes
## from its pointer, and the writable slice spelling is `[mut T]` — which `str` is not.
##
## Measured on the parent (d18fb3f): the program BUILT clean and the binary died with SIGSEGV
## (x86_64 exit 139) writing into `.rodata`; aarch64 and riscv64 reached a fail-loud trap (133)
## and wasmtime aborted (134). Four backends, four different answers, none of them a diagnostic.
## Now all four refuse in `check`, before any emit, at the write.
main := fn() -> u64 {
  s := "abc"
  s[0] = 65
  7
}
