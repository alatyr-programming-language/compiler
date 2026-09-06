## e2e — Issue #404 / Stdlib appendix §6 + §8.5 + §2.4 + Modules §3: `HashMap`'s iterator protocol
## must be reachable through the QUALIFIED path from a module that is not a descendant of
## `alloc::hashmap`. §6 fixes the closed v1 surface of `HashMap(K, V)` and names `iter` in it, §8.5
## makes the §6 alloc-tier types required content given an allocator, §2.4 makes the returned type an
## iterator through `next(in out self) -> Opt`, and Modules §3 fixes the external surface as exactly
## the pub-chain-to-root-reachable one.
##
## Failure-first on parent 8370bd2 (x86_64, default build path): the map-entry `alloc::hashmap::iter`
## is ALREADY `pub`, yet the qualified call on line 38 below is rejected with
## `alatyr: check: invalid at line 38 in issue404_qualified_hashmap_protocol`. The private overloads
## of the SAME two names in the SAME module are what fail the visibility test, because `sema_vis_pair`
## (`src/sema.al`) reports a violation when ANY same-name, same-module declaration is invisible, not
## when every candidate is (#403). Measured in three lib variants on that one parent compiler binary:
## neither marker -> rejected at the map-entry `iter` line 38; `iter` published only -> the rejection
## MOVES to the qualified `next` on line 40; both published -> this program builds and answers 42.
##
## The two `iter` overloads are exercised at DIFFERENT instantiations on purpose (#404 criterion 4).
## Both mangle from the type arguments alone, so `iter(u64, u64, ptr(m), a)` and `iter(u64, u64, it)`
## in ONE program both emit `alloc__hashmap__iter__u64__u64` and `as` refuses the assembly — a
## pre-existing defect of the same family as #455, present on the parent through the bare spelling and
## independent of these markers. Instantiating the identity at `(u64, u32)` keeps the two overloads
## distinguishable without depending on that defect.
##
## `unwrap` is deliberately NOT used to open the `Option(Entry(K, V))`: `unwrap` over an Option of a
## GENERIC struct answers a wrong value on the parent (the second field reads back as 0), which is a
## separate wrong-value defect filed on its own; `match` reads both fields correctly. Every rejection
## code below is distinct and < 126, and nothing is summed into a single total.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)

  ## ---- an EMPTY map: the protocol must yield nothing at all -------------------------------
  mut m0 := alloc::hashmap::new(u64, u64, ptr(ar))
  mut c0 := alloc::hashmap::iter(u64, u64, ptr(m0), ar)   ## the map-entry overload, QUALIFIED
  if c0.i != 0 { return 1 }
  match alloc::hashmap::next(u64, u64, c0) {              ## §2.4 `next`, QUALIFIED
    Option::Some(x) => { return 2 }
    Option::None => { }
  }

  ## ---- ONE entry: yielded once, then the walk ENDS and stays ended ------------------------
  mut m1 := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m1), ar, 5, 7).expect("insert 5")
  mut c1 := alloc::hashmap::iter(u64, u64, ptr(m1), ar)
  match alloc::hashmap::next(u64, u64, c1) {
    Option::Some(e) => {
      if e.key != 5 { return 3 }
      if e.val != 7 { return 4 }
    }
    Option::None => { return 5 }
  }
  match alloc::hashmap::next(u64, u64, c1) {
    Option::Some(x) => { return 6 }
    Option::None => { }
  }
  match alloc::hashmap::next(u64, u64, c1) {              ## an exhausted iterator stays exhausted
    Option::Some(x) => { return 7 }
    Option::None => { }
  }

  ## ---- THREE entries: each key seen exactly once, with its own value ----------------------
  mut m3 := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m3), ar, 1, 10).expect("insert 1")
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m3), ar, 2, 20).expect("insert 2")
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m3), ar, 3, 30).expect("insert 3")
  mut c3 := alloc::hashmap::iter(u64, u64, ptr(m3), ar)
  mut n1 : u64 = 0
  mut n2 : u64 = 0
  mut n3 : u64 = 0
  mut steps : u64 = 0
  mut walking : bool = true
  while walking {
    match alloc::hashmap::next(u64, u64, c3) {
      Option::Some(e) => {
        steps = steps + 1
        if steps > 3 { return 8 }
        if e.key == 1 {
          if e.val != 10 { return 9 }
          n1 = n1 + 1
        }
        if e.key == 2 {
          if e.val != 20 { return 10 }
          n2 = n2 + 1
        }
        if e.key == 3 {
          if e.val != 30 { return 11 }
          n3 = n3 + 1
        }
        if e.key < 1 { return 12 }
        if e.key > 3 { return 13 }
      }
      Option::None => { walking = false }
    }
  }
  if n1 != 1 { return 14 }
  if n2 != 1 { return 15 }
  if n3 != 1 { return 16 }
  if steps != 3 { return 17 }

  ## ---- the PROTOCOL IDENTITY `iter` overload, qualified, at its own instantiation ---------
  mut m4 := alloc::hashmap::new(u64, u32, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u32, ptr(m4), ar, 9, 11).expect("insert 9")
  mut c4 := alloc::hashmap::hashmap_iter(u64, u32, ptr(m4), ar)
  d4 := alloc::hashmap::iter(u64, u32, c4)               ## §2.4 iterable — the identity, QUALIFIED
  if d4.i != c4.i { return 18 }
  if d4.cap != c4.cap { return 19 }
  if d4.base != c4.base { return 20 }
  match alloc::hashmap::next(u64, u32, c4) {
    Option::Some(e) => {
      if e.key != 9 { return 21 }
      if u64(e.val) != 11 { return 22 }
    }
    Option::None => { return 23 }
  }
  match alloc::hashmap::next(u64, u32, c4) {
    Option::Some(x) => { return 24 }
    Option::None => { }
  }
  ## the identity copy is independent of the place it copied: advancing `c4` did not move `d4`
  if d4.i != 0 { return 25 }

  42
}
