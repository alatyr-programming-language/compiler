## e2e reject — #1663: `ptr(mut v)` over an immutable local. Memory §4.4: "an immutable place yields only
## `ptr(T)`", "A permission may only be dropped, never gained". The parser drops the `mut` qualifier, so
## the refusal reads it back off the source; a plain `ptr(v)` of the same place stays legal (§4.4's
## permitted read-only pointer). MEASURED on the parent (`21973d25`, native x86_64): `check` rc 0, ran 42.
## expect: reject "check: immutable binding" "at line 8"
main := fn() -> u8 {
  v : u64 = 2
  p := ptr(mut v)
  u8(deref(p) + 40)
}
