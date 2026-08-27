## Issue #167 FFI witness: C hands an Alatyr @abi(c) function a pointer to a two-byte struct.
## The Alatyr store must update only `b`; the C guard immediately after the struct must remain intact.
P8 := struct { a : u8, b : u8 }

@export("issue167_setb") issue167_setb := @abi(c) fn(p : ptr(mut P8)) {
  deref(p).b = 9
}

drive := @extern @abi(c) fn() -> i64

main := fn() -> u64 {
  u64(drive())
}
