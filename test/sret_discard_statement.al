## A wide-SRET call whose result is DISCARDED (statement position, not the tail) must still be given
## a destination. The SysV convention has the callee write the whole struct through the hidden
## pointer in %rdi; with no binding to publish one, `emit_call_args` skipped its `leaq` and the
## `call` went out anyway, so the callee wrote 72 bytes through whatever %rdi happened to hold.
##
## It faulted only when no earlier wide-SRET call in the same frame had left a usable pointer
## behind — `d := mk()` before the bare call masked it by leaving its own destination live, which is
## why this fixture keeps the bare call FIRST and binds nothing before it (#711).
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }

mk := fn(n : u64) -> S9 {
  return S9(a = n, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9)
}

main := fn() -> u64 {
  mk(1)
  d := mk(1)
  return d.h + 34
}
