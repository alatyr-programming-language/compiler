## #1397 — two generic calls compared inside a GENERIC body, whose type argument is the enclosing type
## parameter (`id(T, a) == id(T, b)` at `T = E`). By Stdlib appendix §2.6 the first `eqv` is false and the
## second true. The x86_64 routing types a generic call's result only from a concrete type argument, so
## the build must stop at the comparison's source line rather than compare word 0 (where `E.T(4, 5)` and
## `E.T(4, 6)` read equal).

E := enum { U, A(u64), T(u8, u64) }
id := fn(T : type, v : T) -> T { v }
eqv := fn(T : type, a : T, b : T) -> bool { id(T, a) == id(T, b) }

main := fn() -> u64 {
  if eqv(E, E.T(4, 5), E.T(4, 6)) { return 12 }
  if not eqv(E, E.T(4, 5), E.T(4, 5)) { return 13 }
  42
}
## expect: reject "result with a multi-word struct/enum value is not yet supported"
