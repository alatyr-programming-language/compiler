## Checked-mode bounds trap for `bytes(s)[i]` — the SPEC-canonical str byte access (`str` is `[u8]`,
## appendix 160 §3.5). The view carries the str's {ptr, len} pair, so the index is checked against
## that RUNTIME len exactly like the `s[i]` str-local read (I11 §358 / CG-7): `cmpq %rbx, %r8; jb;
## ud2` → SIGILL, shell status 132. Registered `run_x86` — the str byte index is an x86_64-only
## surface today (a64/rv64/wasm fail loud on every str index). Dropped in an `unchecked` scope.
##
## FAILURE-FIRST: this arm was the one view-byte-index shape with NO bounds check at all. Measured on
## the parent compiler, the program below ran to a NORMAL exit carrying whatever byte sat past the
## literal's `.rodata` run — a silent wrong value, not a trap. The in-range read runs first, so a
## compiler that trapped on EVERY `bytes(s)[i]` would fail this row too.
##
## `s` has len 6 and the neighbouring bytes are non-zero and pairwise distinct, so an in-range read
## cannot be confused with a wrong-address read; `i = 9` is past the end.
main := fn() -> u64 {
  s := "AbCdEf"
  if u64(bytes(s)[2]) != 67 { return 100 }
  i := 9
  return u64(bytes(s)[i])
}
