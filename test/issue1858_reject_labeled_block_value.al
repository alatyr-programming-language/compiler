## Issue #1858 — a labeled block in value position, `x := @label(name) { … }`, is refused, located,
## rather than parsed as a `loop` whose keyword it does not have.
main := fn() -> u64 {
  mut r : u64 = 40
  x := @label(blk) {
    r = 42
    r
  }
  x
}
## expect: reject "not implemented yet (#1858)" "at line 5"
