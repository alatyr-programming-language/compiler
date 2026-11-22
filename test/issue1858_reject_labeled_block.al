## Issue #1858 — a labeled block `@label(name) { … }` (Grammar §3.7) is not implemented. Its body was
## dropped on every backend, a silent 40 for the due 42. Until it is implemented it is refused, located.
main := fn() -> u64 {
  mut v : u64 = 40
  mut r : u64 = 0
  @label(blk) {
    mut v : u64 = 0
    v = 2
    r = v
  }
  v + r
}
## expect: reject "not implemented yet (#1858)" "at line 6"
