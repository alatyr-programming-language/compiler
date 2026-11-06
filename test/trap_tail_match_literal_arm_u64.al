## e2e (#1248) — control: the same tail `match` arm in a function returning `u64` is a `u64`
## subtraction, and `5 - 7` borrows. It stays refused at run time (the checked guard traps), never a
## wrapped value (Concurrency §6.5, spec v1.6.0).
##
## Expected: trap on all four backends (132 / 133 / 133 / 134).
## Measured on the parent (`9acadf0b`, native x86_64, compiler built by the seed and self-built alike):
## the same traps, 132 / 133 / 133 / 134.
f := fn(k : u64) -> u64 {
  match k { 0 => { 7 }; _ => { 5 - 7 } }
}
main := fn() -> u64 {
  if f(3) == 0 { return 3 }
  return 42
}
## expect: trap
