## Issue #1808 — inside a generic's body its type parameter `T` names the parameter, which shadows a
## module-level declaration of the same name (`T := u8` below). The instance `outer` needs is `inner` at
## the type `outer` was instantiated at, `u64`. When the mono pre-pass resolved `T` in `inner(T, h)` as
## the global alias before substituting the parameter, it registered `inner` at `u8`, the call named
## `…__inner__u64`, and the link failed. Each instance reads the full 64-bit word: 42.
T := u8
inner := fn(T : type, h : usize) -> u64 { p : ptr(T) = unchecked bitcast(ptr(T), h); u64(deref(p)) }
outer := fn(T : type, h : usize) -> u64 { inner(T, h) }
main := fn() -> u64 {
  mut x : u64 = 42
  outer(u64, unchecked bitcast(usize, ptr(x)))
}
## spec: Declarations §6.1; Comptime §3.2
## expect: run 42
