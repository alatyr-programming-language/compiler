## e2e / issue #393 (residual) — a program that spells its variant patterns BARE must still get the
## ambient base prelude. Control Flow §5.2 makes the bare name, the `::`-path and the `.`-spelling
## three spellings of ONE variant — "the scrutinee's enum type supplies the context … All three forms
## denote the same variant" — so `Ok(h)` / `OutOfMemory` is as legal as any qualified spelling.
##
## `cli::ambient_paths` injects that prelude by SCANNING THE SOURCE TEXT, and until this fix the only
## text that pulled the allocator surface was the bare name of the fallible-result type. A file whose
## patterns are all bare need never contain that word — this one does not, in code or in comment —
## so no prelude was injected and `arena_over`, `allocate` and the allocator error variants were all
## rejected as unbound names: a valid program refused because of how its patterns were spelled.
## The same scan is why the defect was first seen through `alatyr fmt`: any tool that rewrites source
## can delete a file's last occurrence of a scanned word and silently change which prelude it gets.
##
## The trigger under test here is the ARENA CONSTRUCTOR, alone: this file names no arena TYPE and no
## allocator ERROR type, so it fails on the parent unless `arena_over` itself pulls the prelude. Its
## two siblings isolate the other two names. On the parent it is refused with `check: unbound name`,
## located on the first constructor call below.
##
## 42 means every check held. Each miss owns its own code from 100 up — never a sum or a product, so
## one wrong branch cannot alias a passing run.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  nofd := unchecked bitcast(usize, neg1)
  m := unchecked sys_mmap(9, 0, 65536, 3, 34, nofd, 0)
  bp := unchecked bitcast(ptr(mut bits8), m)

  ## 64 bytes of room: an 8/8 request is served.
  mut a := arena_over(bp, 64)
  mut first := 0
  r := allocate(a, u8, 8, 8)
  match r {
    Ok(h) => { first = 1 }
    Err(e) => {
      match e {
        OutOfMemory => { first = 2 }
        BadAlignment => { first = 3 }
        SizeTooLarge => { first = 4 }
      }
    }
  }
  if first != 1 { return 100 }

  ## 8 bytes of room and a 9-byte request: the exhaustion arm, still spelled bare.
  mut b := arena_over(bp, 8)
  mut second := 0
  r2 := allocate(b, u8, 9, 1)
  match r2 {
    Ok(h2) => { second = 1 }
    Err(e2) => {
      match e2 {
        OutOfMemory => { second = 2 }
        BadAlignment => { second = 3 }
        SizeTooLarge => { second = 4 }
      }
    }
  }
  if second != 2 { return 101 }

  return 42
}
