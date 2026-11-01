## e2e — #942, Types §4.2/§4.3: a fn's tail is a value sink of its declared result just like an early
## `return`. `x` is an `i64` parameter and the result is `u64`, so the tail needs the explicit `u64(x)`;
## without it the program is ill-formed and refused at the tail, on every backend.
f := fn(x : i64) -> u64 {
  x
}
main := fn() -> u64 {
  f(0 - 1) % 256
}
