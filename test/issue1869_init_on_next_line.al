## Issue #1869 — a line-leading `=` continues the declaration (Grammar §2.6; spec#172), so
## `v : [u64; 2]` / `= [40, 2]` is one initialized declaration and `v.len` is 2 (Types §6.4). The source
## recovery stopped at the newline, took `v` for an uninitialized local, and laid out nothing: 40.
main := fn() -> u64 {
  v : [u64; 2]
    = [40, 2]
  v.len + 40
}
## spec: Grammar §2.6; Types §6.4
## expect: run 42
