## #1394 / #1397 — `==` / `!=` with a call to a GENERIC fn returning a multi-word enum. By Stdlib
## appendix §2.6 and Comptime §5.5 both comparisons are true. The x86_64 lowering cannot type a generic
## callee's result at the comparison yet, so the build stops there with the call's source line rather
## than compare the returned tag with the `$0` a multi-word constructor materializes as (the parent
## `ea6651db` builds it and exits 11). Exit 42 = both answers right; 11 or 12 = a wrong answer.

E := enum { U, A(u64), T(u8, u64) }
id := fn(T : type, v : T) -> T { v }

main := fn() -> u64 {
  x := E.T(4, 5)
  if not (id(E, x) == E.T(4, 5)) { return 11 }
  if id(E, x) != E.T(4, 5) { return 12 }
  42
}
## expect: run 42
