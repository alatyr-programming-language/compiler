## #1822 / Functions §2.3, §5.1: a call in STATEMENT position that omits an `in` parameter with no
## default is ill-formed. The checker used to accept it, and the callee read `n` from a stray register.
g := fn(a : u64, n : u64) {
  print("{}\n", n)
}
main := fn() -> u64 {
  g(1)
  return 42
}
## expect: reject "leaves parameter `n` unbound" "at line 7"
