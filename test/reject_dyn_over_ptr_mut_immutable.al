## e2e reject — FN-11 / Functions §1.6 as decided by spec#152: `dyn_over` takes an ORDINARY address-of
## with no carve-out from Memory §4.4, so `ptr(mut s)` over a store declared without `mut` gains a
## permission the place does not have and is ill-formed here exactly as anywhere else. The canonical
## spelling over such a store is `dyn_over(ptr(s))` (`test/dyn_closure.al`). MEASURED on the parent
## (`21973d25`, native x86_64): `check` rc 0, ran 42.
## expect: reject "check: immutable binding" "at line 10"
main := fn() -> u64 {
  a := 30
  s := fn(x : u64) -> u64 { return x + a }
  d : dyn fn(u64) -> u64 = dyn_over(ptr(mut s))
  return d(12)
}
