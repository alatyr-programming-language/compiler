## e2e reject — #1663: `ptr(mut s)` over an immutable STRUCT local. Memory §4.4: "an immutable place
## yields only `ptr(T)`"; the AND-path of §3.3 stops at the binding, whatever the struct's own fields
## say. (`ptr(mut s.a)`, a FIELD address, is already refused by the existing field-address fence, so
## this takes the whole-place route.) MEASURED on the parent (`21973d25`, native x86_64): `check` rc 0.
## expect: reject "check: immutable binding" "at line 9"
S := struct { mut a : u64, b : u64 }
main := fn() -> u8 {
  s := S(a = 2, b = 10)
  p := ptr(mut s)
  r : S = deref(p)
  u8(r.a + r.b + 30)
}
