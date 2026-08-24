## Declarations §3.1 over a CALL result: the callee's own DECLARED return type is the second source
## reliable enough to reject on. `g() -> str` is the two-word {ptr, len} value; binding it to a
## word-sized integer annotation used to pass `check` and return a silent wrong value.
g := fn() -> str {
  return "nope"
}
main := fn() -> u64 {
  x : u64 = g()
  return x
}
