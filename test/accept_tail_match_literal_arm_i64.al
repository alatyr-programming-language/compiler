## e2e (#1248) — a literal-only `+ - *` whose value is a function's result through a STATEMENT tail
## (a trailing `match` arm, an `if` branch, an `unchecked` block) takes the declared result type, so
## its checked guard is the signed one and `5 - 7` is `-2`, not a borrow.
##
## Concurrency §6.5 (spec v1.6.0): the guard an operation carries is chosen by the operand types; a
## literal takes its type from its context (Types §2.3), here the function's result `i64`.
##
## Expected: 42 on x86_64, aarch64, riscv64 and wasm.
## Measured on the parent (`9acadf0b`, native x86_64, compiler built by the seed and self-built alike):
## this file traps 132 / 133 / 133 / 134 (the unsigned borrow guard). Per function on `2cf60b45`: `f`,
## `g` and `h` each trapped 132 / 133 / 133 / 134; `u` exited 42 on x86_64, aarch64 and riscv64 and
## trapped 134 on wasm.
f := fn(k : u64) -> i64 {
  match k { 0 => { 7 }; _ => { 5 - 7 } }
}
g := fn(k : u64) -> i64 {
  if k == 0 { return 9 }
  match k { 1 => { 7 }; _ => { if k == 2 { 0 - 1 } else { 5 - 7 } } }
}
h := fn(k : u64) -> i64 {
  if k == 0 { 7 } else { match k { 1 => { 1 }; _ => { 5 - 7 } } }
}
u := fn(k : u64) -> i64 {
  unchecked { match k { 0 => { 7 }; _ => { 5 - 7 } } }
}
main := fn() -> i64 {
  if f(3) != -2 { return 1 }
  if g(3) != -2 { return 2 }
  if g(2) != -1 { return 3 }
  if h(3) != -2 { return 4 }
  if u(3) != -2 { return 5 }
  if f(0) != 7 { return 6 }
  return 42
}
## expect: run 42
