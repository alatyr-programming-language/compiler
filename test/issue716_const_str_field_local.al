## Issue #716 — a local bound from a module-const struct's `str` FIELD (`v := APP.name`) and passed to a
## call. `collect_slots` sized `v`'s slot through an inline `match deref(v)` that the lowering could not
## type: its `Field` arm was compared against tag 0 and never taken, so the slot got ONE scalar word while
## `emit_st_assign` stored the resolved two-word `str`. On the parent this built and ran to 41 (the call
## read a length of 4 where 5 was stored); it runs to 42 once both ask the same `const_field_rhs`.
App := struct { name : str, n : u64 }
APP := App(name = "hello", n = 7)
len_of := fn(s : str) -> u64 { s.len }
main := fn() -> u64 {
  v := APP.name
  return len_of(v) + 37
}
