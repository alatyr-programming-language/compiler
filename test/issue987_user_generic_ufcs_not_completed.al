## e2e / issue #987 — the lowerer completes an implicit auto-ref call into its explicit form only for a
## callee declared in `alloc::vec`, never for a user generic over a user generic struct.
##
## #987's fix writes `v.at(i)` as the explicit `alloc::vec::at(S, ptr(v), i)`, the form measured right
## for a `Vec` element. A user generic is not that form: the explicit `bget(E, ptr(be))` over
## `Box(T) := struct { v : T, tag : u64 }` already answers a wrong value on x86_64 when `E` is an enum
## (#1654). Completing `be.bget()` into it turned the implicit call's segfault into a silent wrong value
## (36 for 42 here). A trap is acceptable, a wrong value is not, so this call keeps the implicit form
## until #1654 makes the explicit one right; then its x86_64 row goes and this file answers 42.
##
## Each check owns a code from 100 up; 42 means all held.
##
## PR #1650's previous head `e7124b23` (x86_64, omen): exit 100 (`be.bget()` read the payload as 1,
## not 7). Its base `837d4614`: SIGSEGV, as here.
Box := fn(T : type) -> type { struct { v : T, tag : u64 } }
bget := fn(T : type, b : ptr(Box(T))) -> T { deref(b).v }

E := enum { X, Y(u64) }
val := fn(e : E) -> u64 { match e { E.Y(k) => { k }; E.X => { 1 } } }

main := fn() -> u64 {
  be : Box(E) = Box(E)(v = E.Y(7), tag = 1)
  e := be.bget()
  if val(e) != 7 { return 100 }
  35 + val(e)
}

## expect: run 42
