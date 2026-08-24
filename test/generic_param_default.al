## FN-5: a GENERIC callee may still fill an omitted trailing value-param default after the explicit
## type argument. `pick(u64, 30, 2)` binds `b`; `pick(u64, 0)` omits it and receives the default 10.
pick := fn(T : type, a : T, b : T = 10) -> T { a + b }

main := fn() -> u64 {
  x := pick(u64, 30, 2)
  y := pick(u64, 0)
  x + y
}
