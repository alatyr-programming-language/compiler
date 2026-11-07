## e2e - a POINTER key through `HashMap`, in CHECKED code (#1081; Stdlib appendix §2.6, Memory §4.5).
##
## Measured on the parent of this change: `lib/base/derive.al` had NO `Pointer` arm at all
## (`git show HEAD~1:lib/base/derive.al | grep -c Pointer` -> 0), and the structural `hash` fell
## through to `return u64(v)` at `lib/base/derive.al:149`. Over a pointer that is a `T(value)`
## conversion, and Types §4.4 gives reinterpret ONE form: "the derived arm cannot be spelled
## `u64(self)` over a pointer: `T(value)` preserves a value or re-brands it, and reading address bits
## out of a pointer is **reinterpret**, whose only form is `bitcast`". It was accepted SILENTLY -
## measured, a checked `u64(p)` over `p : ptr(u64)` builds and exits with the address's low byte
## (rc=88), no refusal and no diagnostic - which is the worse failure the issue names: nothing goes
## red, the hash just has a mechanism the spec does not recognise.
##
## WHAT THE SPEC REQUIRES, QUOTED (spec 1.8.0)
##
## Memory §4.5: "A derived `Eq`/`Ord`/`Hash` over a whole pointer reaches that read too, but **granted
## where it is generated**: Stdlib appendix §2.6's derive expands to library code that spells its
## `Pointer` arm as `unchecked bitcast(usize, ...)`, so the crossing is named and granted inside the
## generated body and the author's checked call site needs no grant of its own - `hash(p)` and `p == q`
## are legal in checked code because the grant is not the author's to write".
##
## Stdlib appendix §2.6: a `Pointer` leaf "compares **by its address bits**, which is the only thing a
## pointer has", and "The pointer stays an **opaque key** to a checked caller - equal pointers hash
## alike, different pointers need not."
##
## WHAT THIS FIXTURE PINS, AND WHY EACH PART IS NEEDED
##
##   probe                                                     code        why
##   A  same address -> same hash, and `eq` true             100-101   §2.6's consistency MUST: the map
##                                                                      found it, so hash and eq agree
##   B  the map finds a SECOND HANDLE on the same address    102-105   THE DISCRIMINATOR: `usize(hash(k))
##                                                                      % cap` is the map's own bucket
##                                                                      spelling (hashmap.al:165), so equal
##                                                                      pointers land in one bucket and `eq`
##                                                                      settles the lookup there
##   C  a DIFFERENT pointer holding the SAME value misses     106-107   the key is IDENTITY, not content:
##                                                                      x and y both hold 11
##   D  a second handle OVERWRITES, no second entry          108-110   `len` stays 1, the value is the new
##                                                                      one, read back through the FIRST handle
##   E  a REHASH keeps every pointer key                    111-117     `insert` rehashes when
##                                                                      `(live + 1) * 4 > cap * 3`
##                                                                      (hashmap.al:162) - at cap 8 that is the
##                                                                      insert that makes live 7 - and `rehash`
##                                                                      spells `hash(K, k)` EXPLICITLY
##                                                                      (hashmap.al:130) while `insert`/`get`
##                                                                      call the implicit `hash(key)`: a fix
##                                                                      that reached only one of the two loses
##                                                                      every key here
##   F  a never-inserted address stays absent                 118       the map does not answer "found" for
##                                                                      every query
##   G  a pointer-BEARING STRUCT key reaches the same arm   119-121   `eq`/`hash` walk the FIELD
##                                                                      (`eq(f.type, a.(f), b.(f))`,
##                                                                      `hash(f.type, v.(f))`) into the same
##                                                                      `Pointer` leaf, not just a leaf key
##
## NO GRANT OF THE AUTHOR'S. Every `hash(k)`, `eq(a, b)` and every map call above is written in
## checked code with NO `unchecked` of the author's own, and every pointer is taken with `ptr(place)`
## (§4.1) rather than fabricated from an integer - so no key operation in this file carries a grant,
## which is the point: adding one would defeat the test. The two `unchecked` below are `sys_mmap` and
## the arena buffer - acquiring memory, the author's own confined crossing that every `hashmap_*`
## fixture pays (`hashmap_str_key.al`).
##
## WHY NO `lt` APPEARS HERE. `Ord` owes the leaf the same arm (§4.5 names it with `Eq` and `Hash`) and
## `derive.al` now has it, but no path reaches it from a checked program today: the prelude's `lt`
## cannot be called with an explicit type argument (measured: `lt(ptr(u64), k1, k2)` -> `check:
## invalid`), and the implicit `lt(k1, k2)` dies in the compiler with `e3 - sema recorded no integer
## type (record U) ... [spell n=1 layers=0 text=T]` at `lib/base/derive.al:125` BEFORE and AFTER this
## change, because nothing instantiates `derive::lt` at a pointer type. That is the generic-at-a-
## pointer-type gap (#1099), not this one, and it is why #1081 stays on the deviations list until a
## container reaches the arm.
##
## Success is 42; every failure has its own code from 100 up, so a passing run cannot be an alias of a
## failing one.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## A pointer-BEARING key: the derive reaches the `Pointer` leaf THROUGH this field (probe G).
PK := struct { p : ptr(u64) }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)

  ## x and y hold the SAME value: two keys a content-reading key would call equal (probe C).
  mut x : u64 = 11
  mut y : u64 = 11
  mut z : u64 = 33

  k1 : ptr(u64) = ptr(x)
  k1b : ptr(u64) = ptr(x)   ## a second handle on k1's OWN address
  k2 : ptr(u64) = ptr(y)    ## a different address, the same value
  gone : ptr(u64) = ptr(z)  ## never inserted

  ## A - `Hash` consistent with `Eq` (§2.6): equal pointers hash alike and compare equal. Reached here
  ## because the map below instantiates `derive::hash`/`derive::eq` at `ptr(u64)`.
  if hash(k1) != hash(k1b) { return 100 }
  if eq(k1, k1b) != true { return 101 }

  ## B - the map finds a SECOND HANDLE on the same address, in the SAME bucket.
  mut m := alloc::hashmap::new(ptr(u64), u64, ptr(ar))
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, k1, 42).expect("insert k1")
  if usize(hash(k1)) % 8 != usize(hash(k1b)) % 8 { return 102 }
  if not alloc::hashmap::contains(ptr(u64), u64, ptr(m), ar, k1b) { return 103 }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k1b) {
    Option::Some(v) => { if u64(v) != 42 { return 104 } }
    Option::None => { return 105 }
  }

  ## C - a DIFFERENT pointer is NOT found, even holding the same value the stored key holds.
  if alloc::hashmap::contains(ptr(u64), u64, ptr(m), ar, k2) { return 106 }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k2) {
    Option::Some(v) => { return 107 }
    Option::None => { }
  }

  ## D - the second handle OVERWRITES; it does not become a second entry.
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, k1b, 7).expect("overwrite via k1b")
  if alloc::hashmap::len(ptr(u64), u64, ptr(m), ar) != 1 { return 108 }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k1) {
    Option::Some(v) => { if u64(v) != 7 { return 109 } }
    Option::None => { return 110 }
  }

  ## E - grow past the load factor so `insert` REHASHES (cap 8 -> 16), then every pointer key still
  ## resolves: the address-bits hash is stable across the capacity change.
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, k2, 9).expect("insert k2")
  mut w : u64 = 4
  mut q : u64 = 5
  mut t : u64 = 6
  mut u : u64 = 8
  mut b : u64 = 12
  w1 : ptr(u64) = ptr(w)
  q1 : ptr(u64) = ptr(q)
  t1 : ptr(u64) = ptr(t)
  u1 : ptr(u64) = ptr(u)
  b1 : ptr(u64) = ptr(b)
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, w1, 4).expect("insert w1")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, q1, 5).expect("insert q1")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, t1, 6).expect("insert t1")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, u1, 8).expect("insert u1")
  alloc::hashmap::insert(ptr(u64), u64, ptr(m), ar, b1, 12).expect("insert b1 (rehash)")
  if alloc::hashmap::len(ptr(u64), u64, ptr(m), ar) != 7 { return 111 }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k1) {
    Option::Some(v) => { if u64(v) != 7 { return 112 } }
    Option::None => { return 113 }
  }
  match alloc::hashmap::get(ptr(u64), u64, ptr(m), ar, k2) {
    Option::Some(v) => { if u64(v) != 9 { return 114 } }
    Option::None => { return 115 }
  }
  if not alloc::hashmap::contains(ptr(u64), u64, ptr(m), ar, b1) { return 116 }
  if not alloc::hashmap::contains(ptr(u64), u64, ptr(m), ar, w1) { return 117 }

  ## F - a never-inserted address stays absent.
  if alloc::hashmap::contains(ptr(u64), u64, ptr(m), ar, gone) { return 118 }

  ## G - the pointer-BEARING STRUCT key: the derive walks the FIELD into the same `Pointer` arm.
  mut s := alloc::hashmap::new(PK, u64, ptr(ar))
  a1 : PK = PK(p = k1)
  a1b : PK = PK(p = k1b)
  a2 : PK = PK(p = k2)
  alloc::hashmap::insert(PK, u64, ptr(s), ar, a1, 42).expect("insert PK")
  if not alloc::hashmap::contains(PK, u64, ptr(s), ar, a1b) { return 119 }
  if alloc::hashmap::contains(PK, u64, ptr(s), ar, a2) { return 120 }
  if hash(a1) != hash(a1b) { return 121 }

  42
}
## expect: run 42
