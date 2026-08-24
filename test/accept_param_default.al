## e2e — §5.1 in-parameter DEFAULT (FN-5): a call that omits a trailing defaulted param has the default
## expression supplied at the call site. Both paths are exercised: `add(30, 2)` binds `b` explicitly
## (=32); `add(0)` omits `b`, so its default `10` is filled → 10. 32 + 10 = 42.
add := fn(a : u64, b : u64 = 10) -> u64 { a + b }
main := fn() -> u64 {
  x := add(30, 2)      ## explicit b → 32
  y := add(0)          ## default b (10) → 10
  x + y                ## 42
}
