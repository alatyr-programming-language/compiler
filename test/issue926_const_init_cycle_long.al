## e2e / issue #926 — a LONG cycle among module-level comptime initializers is refused like a short one.
##
## Declarations §7.1: "a cycle among comptime initializers is a compile error" — of any length. Twelve
## bindings `A0 … A11`, each one more than the previous and `A0` closing the ring through `A11`. A
## hop-bounded chase (8 const-to-const hops) missed this ring: measured on omen, native x86_64, a
## 10-, 11-, 12- and 20-binding ring each answered `check` rc 0 and `build` **rc 139 SIGSEGV**, the
## same unbounded recursion in `lower::global_init_value` the short cycles had. Sema now enters each
## const at most once per checked declaration, which both terminates and is complete.
##
## `B := A0 + A0` sits OUTSIDE the ring and refers into it twice: the walk from `B` must not refuse `B`
## (it is not on a cycle) and must not explore the ring once per path (it enters each const once).
## The refusal lands on the first declaration of the ring in source order, `A0`, at line 15.
B := A0 + A0
##
A0 := A11 + 1
A1 := A0 + 1
A2 := A1 + 1
A3 := A2 + 1
A4 := A3 + 1
A5 := A4 + 1
A6 := A5 + 1
A7 := A6 + 1
A8 := A7 + 1
A9 := A8 + 1
A10 := A9 + 1
A11 := A10 + 1

main := fn() -> u64 {
  return B
}
## expect: reject "COMPTIME INITIALIZER CYCLE" "at line 15"
