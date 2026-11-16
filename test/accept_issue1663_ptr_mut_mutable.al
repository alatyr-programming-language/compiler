## e2e accept — #1663's control: `ptr(mut …)` over a place whose AND-path IS writable stays legal (Memory
## §4.4: "a mutable place yields `ptr(mut T)` or `ptr(T)`"). A `mut` local, an element of a `mut` array
## and a `mut` module global each give the writable path of §3.3, and each is written through its
## pointer. 30 + 30 + 10 = 70. The read-only `ptr(s)` side is `test/dyn_closure.al`.
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
  deref(w) = 10
  u8(deref(p) + deref(q) + deref(w))
}
