## #1507 / Functions §2.3, §5.1: an argument beyond the declared parameters binds none of them, so the
## call is ill-formed. A forward callee, so the old name walk never compared the counts.
h := fn(x : u64) -> u64 {
  return f(x, 1, 2)
}
f := fn(a : u64, b : u64) -> u64 { a + b }
main := fn() -> u64 { h(41) }
## expect: reject "passes 3 argument(s) to a function that declares 2 parameter(s)" "at line 4"
