## e2e — a POINTER key through `HashMap`, in CHECKED code (#1081; Stdlib §2.6, Memory §4.5).
##
## Measured before this change: `lib/base/derive.al` had NO `Pointer` arm at all
## (`grep -c Pointer lib/base/derive.al` -> 0). The structural `hash(T, v)` ran Struct -> Enum ->
## Array -> Str -> fallthrough, and the fallthrough was `return u64(v)`. Over a pointer that is a
## `T(value)` conversion, and Type System §4.4 says `bitcast` is the ONLY conversion in the reinterpret
## class: `T(value)` preserves a value (widen/narrow/numeric) or re-brands it, and a pointer is in no
## numeric domain (§4.3 confines implicit conversion to widen within one). So `hash(p)` for a
## pointer-bearing key either had no class in the lattice or read address bits by a route §4.5
## confines without naming them — and two conforming implementations could diverge on the same source,
## which is the FND-3 failure the §2.6 rewrite exists to close.
##
## ## What this fixture proves, and why each part is needed
##
## §4.5: "Two pointers compared with each other (`p == q`, `p < q`) … compare by their address bits,
## which is what the structural derive gives a `Pointer` leaf (Stdlib appendix §2.6), and they stay
## LEGAL in checked code." §2.6: the read that gets those bits IS a `bitcast` and it IS granted, but
## "the grant sits in the GENERATED body, not at the user's call site". So what this program tests is
## that **no key operation carries a grant**: every `hash(k)`, `eq(k1, k2)` and `lt(k1, k2)` below is
## written in checked code with no `unchecked` of the author's, and the pointers themselves are taken
## with `ptr(local)` (§4.1) rather than built from an integer by a bitcast, so no key comparison in
## this file is granted anywhere. Adding one to make it compile would defeat the test.
## The two `unchecked` that remain are `page()` and the arena buffer — acquiring memory from the OS,
## which is the author's own confined crossing and not what §2.6/§4.5 speak to; `hashmap_str_key.al`
## pays the same two and for the same reason.
##
##   probe                                                     code
##   A  two distinct addresses are two DISTINCT keys          100-102  non-vacuity: proved by writing
##                                                                       different values through them and
##                                                                       reading both back — if they were the
##                                                                       same address the second write would
##                                                                       have overwritten the first
##   B  a SECOND HANDLE on the SAME address finds the entry  103-105  THE DISCRIMINATOR. `k1b := ptr(x)`
##                                                                       is a different expression with the same
##                                                                       address; a derive that compared
##                                                                       anything but the address bits, or
##                                                                       refused the key, fails here
##   C  `hash` is consistent with `eq` (§2.6)                 106-108  same address -> same hash; the two
##                                                                       distinct addresses must not be forced
##                                                                       equal by a constant hash
##   D  `lt` over pointers is irreflexive and asymmetric     109-111  §4.5 gives the address bits to
##                                                                       `p < q` too; WHICH pointer is smaller is
##                                                                       hardware-defined, so only the LAWS are
##                                                                       asserted, never a chosen order
##   E  the map round-trips pointer keys                     112-117  insert / contains / get / len
##   F  a REHASH keeps every pointer key                     118-125  the 7th insert crosses (live+1)*4 >
##                                                                       cap*3 at the default 8 buckets;
##                                                                       `rehash` spells `hash(K, k)` explicitly
##                                                                       while insert/get call the implicit
##                                                                       `hash(key)`, so a fix that reached only
##                                                                       one of the two loses every key here
##   G  an absent pointer stays absent                       126      a never-inserted address must not
##                                                                       resolve — the map is not answering
##                                                                       "found" for every query
##
## Every failure has its own code from 100 up; success is 42 (#386 — no summed discriminator, so a
## passing run cannot be an alias of a failing one).

sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## one fresh anonymous mapping, the same shape `hashmap_str_key.al` uses
page := fn(n : usize) -> usize {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(std::sysno::MMAP, 0, n, 3, 34, bitcast(usize, neg1), 0)
  unchecked bitcast(usize, r)
}

main := fn() -> u64 {
  ap := page(65536)
  bp := unchecked bitcast(ptr(mut bits8), ap)
  mut ar := arena_over(bp, 65536)

  ## three distinct objects; their addresses are the keys
  mut x : u64 = 11
  mut y : u64 = 22
  mut z : u64 = 33

  ## ANNOTATED, not inferred: `ptr(local)` yields a pointer whose pointee the sema does not record
  ## (`AddrOf` returns `TyPtr` with no span, src/sema.al:11352-11356), so an inferred `k1 := ptr(x)`
  ## reaches `hash(k1)` with no `T` to instantiate and is refused (Comptime §3.3). The annotation is
  ## the strict form the catalogue prescribes, and it is what makes the checked call below legal.
  k1 : ptr(u64) = ptr(x)
  k2 : ptr(u64) = ptr(y)
  k3 : ptr(u64) = ptr(z)

  ## A — non-vacuity, with no bitcast: distinct addresses hold distinct values after both writes.
  if deref(k1) != 11 { return 100 }
  if deref(k2) != 22 { return 101 }
  if deref(k1) == deref(k2) { return 102 }

  ## B — a second handle on k1's own address.
  k1b : ptr(u64) = ptr(x)

  ## C — Hash consistent with Eq (§2.6): the same address hashes alike, and the hash is not a
  ## constant (a constant hash would make every key collide, which D and F below would not catch).
  if hash(k1) != hash(k1b) { return 103 }
  if eq(k1, k1b) != true { return 104 }
  if hash(k1) == hash(k2) { return 105 }

  ## D — the LAWS of the address-bits order, never a chosen winner.
  if lt(k1, k1) != false { return 106 }
  if lt(k1, k2) == lt(k2, k1) { return 107 }
  if lt(k1, k1b) != false { return 108 }

  ## E — the map round-trips pointer keys, in checked code.
  mut m := alloc::hashmap::new(ptr(u64), u64, ptr(ar))
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, k1, 7).expect("insert k1")
  if alloc::hashmap::len(ptr(u64), u64, ptr(m), ar) != 1 { return 109 }
  if not alloc::hashmap::contains(ptr(u64), u64, ptr(m), ar, k1b) { return 110 }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k1b) {
    Option::Some(v) => { if u64(v) != 7 { return 111 } }
    Option::None => { return 112 }
  }

  ## the second handle must NOT become a second entry
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, k1b, 8).expect("overwrite via k1b")
  if alloc::hashmap::len(ptr(u64), u64, ptr(m), ar) != 1 { return 113 }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k1) {
    Option::Some(v) => { if u64(v) != 8 { return 114 } }
    Option::None => { return 115 }
  }

  ## k2 and k3 are distinct keys
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, k2, 9).expect("insert k2")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, k3, 10).expect("insert k3")
  if alloc::hashmap::len(ptr(u64), u64, ptr(m), ar) != 3 { return 116 }
  if not alloc::hashmap::contains(ptr(u64), u64, ptr(m), ar, k3) { return 117 }

  ## F — cross the load factor so the map REHASHES, then every key must still resolve, checked ONE
  ## AT A TIME (no summed discriminator).
  mut w : u64 = 44
  mut q : u64 = 55
  mut r : u64 = 66
  mut s : u64 = 77
  mut t : u64 = 88
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, ptr(w), 4).expect("w")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, ptr(q), 5).expect("q")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, ptr(r), 6).expect("r")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, ptr(s), 7).expect("s")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, ptr(t), 8).expect("t")
  if alloc::hashmap::len(ptr(u64), u64, ptr(m), ar) != 8 { return 118 }

  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k1) {
    Option::Some(v) => { if u64(v) != 8 { return 119 } }
    Option::None => { return 120 }
  }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k2) {
    Option::Some(v) => { if u64(v) != 9 { return 121 } }
    Option::None => { return 122 }
  }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k3) {
    Option::Some(v) => { if u64(v) != 10 { return 123 } }
    Option::None => { return 124 }
  }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, ptr(t)) {
    Option::Some(v) => { if u64(v) != 8 { return 125 } }
    Option::None => { return 126 }
  }

  ## G — a never-inserted address stays absent.
  mut gone : u64 = 99
  if alloc::hashmap::contains(ptr(u64), u64, ptr(m), ar, ptr(gone)) { return 127 }

  42
}
