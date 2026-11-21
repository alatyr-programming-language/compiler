## #1822 / Functions §2.3, §5.1: the same omission in VALUE position, callee declared first. It was
## refused before, but as an unbound name, which names nothing that is wrong; the diagnostic now names
## the parameter.
f := fn(a : u64, b : u64) -> u64 { a + b }
main := fn() -> u64 {
  return f(2)
}
## expect: reject "leaves parameter `b` unbound" "at line 6"
