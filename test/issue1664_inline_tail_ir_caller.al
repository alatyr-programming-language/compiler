## e2e — #1664's CONTROL: the same `@inline` statement body, with a caller the shared IR DOES build.
## `main` holds no `f64`, so every function here is IR-built and the substitution happens in the IR
## builder (`ib_inline_subst`, #1074/#1084), which already answers the body's final expression: this
## fixture passed on the parent on the default path and failed only on `x86-legacy`. It stays to prove
## the legacy fix did not disturb the IR path. 42 = g(1 + 1) = 2 * 21.
g := fn(x : u64) -> u64 { x * 21 }
@inline mid := fn(k : u64) -> u64 {
  b : u64 = k + 1
  g(b)
}
main := fn() -> u64 {
  mid(1)
}
## expect: run 42
