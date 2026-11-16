## e2e reject — #1663: an IMMUTABLE module global bound to an `out` / `in out` parameter. Memory §3.1
## makes a binding without `mut` immutable, and that holds at module scope as it does in a frame, so the
## place argument fails Functions §2.3's MUST at its only step. This is the `perm == 2` answer of
## `sema_write_mutability` (`src/sema.al:17344`) reached through the CALL route: the store route refused
## `g = 30` there already, and `test/accept_issue1663_mutable_place_args.al` exercises only the writable
## `mut g`. The callee's `x = 30` wrote the caller's global.
## expect: reject "check: immutable binding" "at line 11"
g : u64 = 0
put := fn(in out x : u64) { x = 30 }
main := fn() -> u8 {
  put(g)
  u8(g + 12)
}
