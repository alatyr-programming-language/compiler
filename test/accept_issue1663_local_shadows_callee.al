## e2e accept — #1663: a LOCAL fn value that shadows a module-level fn of the same name (Declarations
## §6.1) is the callee, so the place-argument fence must not apply the module fn's `in out` signature.
## The local `put` takes `x` by value; passing the immutable `v` to it is well-formed. Refused on the
## parent with an immutable-binding diagnostic located at the call (line 11), because the fence looked
## the bare name up among module-level fns only. The local runs: 2+1=3, +9 → 12.
## expect: run 12
put := fn(in out x : u64) { x = 30 }
main := fn() -> u8 {
  put := fn(x : u64) -> u64 { x + 1 }
  v : u64 = 2
  r := put(v)
  u8(r + 9)
}
