## #1516 / Functions §2.3: a call to a function declared LATER in the module is held to the same rule.
## It used to build, and `h(40)` answered 40 with `b` read from a stray register.
h := fn(x : u64) -> u64 {
  return f(x)
}
f := fn(a : u64, b : u64) -> u64 { a + b }
main := fn() -> u64 { h(40) }
## expect: reject "leaves parameter `b` unbound" "at line 4"
