## e2e accept — #1663's other control: `ptr(mut …)` over a place that IS writable stays legal, and so
## does the read-only `ptr(k)` of an immutable place (Memory §4.4: "a mutable place yields ptr(mut T)
## or ptr(T)"; "an immutable place yields only ptr(T)"). A `mut` local, an element of a `mut` array and
## a `mut` module global each give the writable AND-path of §3.3; `k` is read back through a plain
## pointer, which §4.4 permits. 30 + 30 + 8 + 2 = 70. (`ptr(mut s.a)`, a field address, is refused by
## the existing field-address fence on the parent too, so no aggregate appears here.)
## expect(x86_64): run 70
mut g : u64 = 0
main := fn() -> u8 {
  mut v : u64 = 2
  p := ptr(mut v)
  deref(p) = 30
  mut arr : [u64; 2] = [1, 0]
  q := ptr(mut arr[1])
  deref(q) = 30
  w := ptr(mut g)
  deref(w) = 8
  k : u64 = 2
  z := ptr(k)
  u8(deref(p) + deref(q) + deref(w) + deref(z))
}
