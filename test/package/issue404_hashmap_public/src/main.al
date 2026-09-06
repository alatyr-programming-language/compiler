## Issue #404 / Stdlib appendix §6 + §8.5 — an EXTERNAL package reaches the public `HashMap`
## iterator protocol. §6 fixes the closed v1 surface of `HashMap(K, V)` and names `iter` in it, §8.5
## makes the §6 alloc-tier types required content given an allocator, §2.4 fixes the protocol as
## `iter`/`next`, and Modules §3 makes the external API exactly the pub-chain-reachable surface.
##
## Failure-first on parent 8370bd2: `alatyr check package.al` in this directory answers rc=1 with
## `alatyr: check: invalid at line 27 in main` — the qualified `alloc::hashmap::iter(u64, u64,
## ptr(m), ar)` below. The map-entry `iter` is already `pub` there; the private overloads of the same
## name in the same module are what fail the visibility test (#403), which is why publishing the
## protocol pair is what makes this reachable. `test/issue404_qualified_hashmap_protocol.al` owns the
## single-file measurement and the empty/one/many/exhausted walk; this consumer proves the same
## surface is reachable from a package that is not part of the compiler's own tree.
##
## `match` opens the `Option(Entry(K, V))` rather than `unwrap`, which answers a wrong value over an
## Option of a generic struct on the parent (filed separately). Every rejection code is distinct
## and < 126.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)

  mut m := alloc::hashmap::new(u64, u64, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, u64, ptr(m), ar, 6, 8).expect("insert 6")
  mut it := alloc::hashmap::iter(u64, u64, ptr(m), ar)      ## §6's `iter`, QUALIFIED
  if it.i != 0 { return 1 }

  match alloc::hashmap::next(u64, u64, it) {                ## §2.4's `next`, QUALIFIED
    Option::Some(e) => {
      if e.key != 6 { return 2 }
      if e.val != 8 { return 3 }
    }
    Option::None => { return 4 }
  }
  match alloc::hashmap::next(u64, u64, it) {                ## the walk ends after the one entry
    Option::Some(x) => { return 5 }
    Option::None => { }
  }
  42
}
