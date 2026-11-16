## e2e reject — #1663: `ptr(mut x)` over an `in` PARAMETER. Functions §9's `in-param` admits no `mut`,
## so `x` is an immutable binding (Memory §3.1) and §4.4 gives it only `ptr(T)`. MEASURED on the parent
## (`21973d25`, native x86_64): `check` rc 0, ran 42.
## expect: reject "check: immutable binding" "at line 6"
peek := fn(x : u64) -> u64 {
  p := ptr(mut x)
  deref(p) + 40
}
main := fn() -> u8 {
  u8(peek(2))
}
