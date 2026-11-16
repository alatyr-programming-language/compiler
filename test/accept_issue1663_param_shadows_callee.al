## e2e accept — #1663: a PARAMETER of fn type that shadows a module-level fn of the same name
## (Declarations §6.1) is the callee, so the place-argument fence must not apply the module fn's
## `in out` signature to `put(v)`. Refused on the parent with an immutable-binding diagnostic at the
## call (line 9). `go(inc)` calls `inc` by value: 2+40 → 42.
## expect: run 42
put := fn(in out x : u64) { x = 30 }
go := fn(put : fn(u64) -> u64) -> u64 {
  v : u64 = 2
  put(v)
}
inc := fn(x : u64) -> u64 { x + 40 }
main := fn() -> u8 { u8(go(inc)) }
