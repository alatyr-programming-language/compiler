## #1172 — a library generic struct named by its whole path, `alloc::vec::Vec(u64)`, is sized as that
## struct: as an enum payload (`Arr(alloc::vec::Vec(u64))`), as the field of a payload struct, and as a
## struct field passed by value (Types §6; Modules §2: a qualified type names its module's declaration).
## Expected exit 42; a failing check exits its own number. NON-VACUOUS: on the parent (main `2ae5d8d9`
## plus #1339's `48f4b584`, x86_64) the fixture exits 1, because `name_tail` kept `vec::Vec` as the type
## name, so the payload got one word and its length read back wrong.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

V := enum {
  Null,
  Arr(alloc::vec::Vec(u64)),
}

Items := struct { k : u64, v : alloc::vec::Vec(u64) }

W := enum {
  Null,
  Box(Items),
}

digits := fn(xs : alloc::vec::Vec(u64)) -> u64 {
  mut n : u64 = 0
  for x in alloc::vec::iter(u64, ptr(xs)) {
    n = n * 10 + x
  }
  n
}

payload_len := fn(v : V) -> u64 {
  match v {
    V.Null => { 0 }
    V.Arr(xs) => { u64(alloc::vec::len(u64, ptr(xs))) }
  }
}

payload_iter := fn(v : V) -> u64 {
  match v {
    V.Null => { 0 }
    V.Arr(xs) => { digits(xs) }
  }
}

boxed_iter := fn(w : W) -> u64 {
  match w {
    W.Null => { 0 }
    W.Box(it) => {
      xs := it.v
      digits(xs) + it.k
    }
  }
}

field_iter := fn(it : Items) -> u64 {
  xs := it.v
  digits(xs) + it.k
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut xs := alloc::vec::new(u64, ptr(ar))
  alloc::vec::push(u64, xs, 7).expect("p")
  alloc::vec::push(u64, xs, 8).expect("p")
  alloc::vec::push(u64, xs, 9).expect("p")
  if payload_len(V.Arr(xs)) != 3 { return 1 }
  if payload_iter(V.Arr(xs)) != 789 { return 2 }
  if boxed_iter(W.Box(Items(k = 1, v = xs))) != 790 { return 3 }
  if field_iter(Items(k = 2, v = xs)) != 791 { return 4 }
  42
}
## expect: run 42
