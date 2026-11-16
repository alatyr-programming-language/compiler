## e2e accept — #1663: an EXPRESSION callee (`fs[0](v)`, FN-6) whose root name is also a module-level
## fn. The parser keeps the root name as the callee span and the callee expression as argument 0, so
## the place-argument fence paired `v` with the module `fs`'s `in out x` and refused the call on the
## parent (line 11). The call goes to the array element `inc`: 2+1=3, +39 → 42.
## expect: run 42
fs := fn(a : fn(u64) -> u64, in out x : u64) { x = 1 }
inc := fn(x : u64) -> u64 { x + 1 }
main := fn() -> u8 {
  fs : [fn(u64) -> u64; 1] = [inc]
  v : u64 = 2
  r := fs[0](v)
  u8(r + 39)
}
