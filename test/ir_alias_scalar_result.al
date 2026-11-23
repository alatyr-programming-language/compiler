## #1864 part 4: a type alias of a kernel scalar (`CE := usize`) is erased (Modules §4.1) and has the
## target's exact representation. The IR builder follows the alias in `ib_type_ks` through
## `sema_vty_name`, so a function returning an aliased scalar is built, and callers are not refused with
## `call: callee result is neither a kernel scalar nor a register-returned aggregate`. 7 + 35 = 42.
CE := usize
ce := fn() -> CE { 7 }
add_ce := fn(a : CE, b : CE) -> CE { a + b }
main := fn() -> usize { add_ce(ce(), 35) }
## expect: run 42
