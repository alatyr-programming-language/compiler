## e2e reject — #1663: `ptr(mut g)` over a module global declared without `mut`. Memory §3.1 holds at
## module scope as in a frame, so §4.4 gives `g` only `ptr(T)`; this is the `perm == 2` answer of
## `sema_write_mutability` reached through the address-of route. MEASURED on the parent (`21973d25`,
## native x86_64): `check` rc 0, ran 40 — the read through the pointer is itself wrong there (#1706).
## expect: reject "check: immutable binding" "at line 8"
g : u64 = 2
main := fn() -> u8 {
  p := ptr(mut g)
  u8(deref(p) + 40)
}
