## e2e — MUTABLE module-level GLOBAL (`mut ACC := 0`). Unlike a constant (compile-time inlined), a
## `mut` global gets runtime `.data` storage at a mangled label `<module>__<NAME>`; reads load it
## (`movq LABEL(%rip), %rax`) and writes store it back. It is shared state: `bump` (a separate fn)
## mutates the SAME cell `main` reads. Six `bump(7)` calls accumulate 42.
mut ACC := 0
bump := fn(n : u64) {
  ACC = ACC + n
}
main := fn() -> u64 {
  mut i := 0
  while i < 6 {
    bump(7)
    i = i + 1
  }
  ACC
}
