## #1822 / Functions §2.3: an `in out` parameter is required, bound by a place argument; a statement
## call that omits it is ill-formed. The callee used to write through whatever the register held.
bump := fn(k : u64, in out s : u64) {
  s = s + k
}
main := fn() -> u64 {
  mut x : u64 = 40
  bump(2)
  return x
}
## expect: reject "leaves parameter `s` unbound: an `out` / `in out` parameter" "at line 8"
