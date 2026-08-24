## Checked-mode integer OVERFLOW trap on `+` (I11 / CG-8, compiler-emitted guard on the native
## `Bin` path — the bare/freestanding dual of num.al's routed `comptime if verify.checked` guard).
## `u64 MAX + 1` overflows unsigned; in a checked context (the default) the compiler-emitted overflow
## guard TRAPS deterministically (x86_64 `jnc`/`ud2`, exit 132). Companion `unchecked_add_ovf` drops
## the guard and wraps to 0. Native-width only — narrow-width keeps its §4 value-model wrap.
main := fn() -> u64 {
  a : u64 = 18446744073709551615
  b := a + 1
  return b
}
