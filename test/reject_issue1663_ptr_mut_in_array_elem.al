## e2e reject — #1663: `ptr(mut xs[1])` over an `in` array parameter. The root binding `xs` is immutable
## (Memory §3.1, #1632's `prov_array_param_in`), so the AND-path to its element is not writable and
## §4.4 permits only `ptr(T)`. The root is the operand's first byte of a postfix chain, which is also
## where `alatyr fmt` reads the qualifier back (the `RECOMPILE` this shape caused in #1682's first
## round). MEASURED on the parent (`21973d25`, native x86_64): `check` rc 0, ran 42.
## expect: reject "check: immutable binding" "at line 8"
peek := fn(xs : [u64; 3]) -> u64 {
  p := ptr(mut xs[1])
  deref(p) + xs[0]
}
main := fn() -> u8 {
  a : [u64; 3] = [2, 40, 10]
  u8(peek(a))
}
