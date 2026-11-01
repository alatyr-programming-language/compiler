## e2e / issue #1302 — a container element that is a multi-word enum or struct, read back through a
## generic library instance, keeps every word.
##
## Three gaps, one shape: the instance reads its element through a pointer whose pointee is its own
## type parameter, and the lowering sized the read as one scalar word.
##   - `vec::get(Option(u64), …)` named a generic-instance type argument (a `Call` node), so the
##     binding of its `Option(Option(u64))` result was sized `Option(T)` with `T` one word;
##   - `Option(T).Some(deref(elem))` delivered the inner discriminant alone;
##   - `slot := dq_elem(T, …)` then `v := deref(slot)` (deque `pop_front` / `pop_back`) and
##     `v := deref(val_at(K, V, …))` (hashmap `get`) bound `v` as one word of a multi-word `T`.
## The programs segfaulted (rc 139) or read a wrong value.
##
## Each check owns a code from 100 up; 42 means every element arrived whole.
## Parent `1262da5d` (x86_64, omen): built rc 0 and stopped with SIGSEGV (rc 139) where 42 was due.
vec := alloc::vec
deque := alloc::deque
hashmap := alloc::hashmap
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

S2 := struct { a : u64, b : u32 }
EN := enum { A(u64), B(u8, i64), C }

optkey := fn(o : Option(u64)) -> u64 {
  match o {
    Option::Some(v) => { return v * 2 + 1 }
    Option::None => { return 0 }
  }
}
enkey := fn(e : EN) -> i64 {
  match e {
    EN::A(x) => { return i64(x) * 4 + 1 }
    EN::B(b, c) => { return i64(b) * 1000 + c }
    EN::C => { return 3 }
  }
}

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 1048576, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 1048576)

  ## the issue's reproduction: an `Option(u64)` payload bound from `vec::get`, passed by value
  mut v := vec::new(Option(u64), ptr(ar))
  p0 := vec::push(Option(u64), v, Option(u64).Some(5))
  o := vec::get(Option(u64), ptr(v), 0)
  match o {
    Option::Some(x) => { if optkey(x) != 11 { return 100 } }
    Option::None => { return 101 }
  }

  ## deque pop_front / pop_back of a two-word struct (`v := deref(slot)` in the instance)
  mut d := deque::deque(S2, ptr(ar), 2)
  p1 := deque::push_back(S2, d, S2(a = 7, b = 4000000001))
  p2 := deque::push_back(S2, d, S2(a = 9, b = 4000000002))
  p3 := deque::push_back(S2, d, S2(a = 11, b = 4000000003))
  f := deque::pop_front(S2, d)
  match f {
    Option::Some(s) => { if s.a != 7 or s.b != 4000000001 { return 102 } }
    Option::None => { return 103 }
  }
  b := deque::pop_back(S2, d)
  match b {
    Option::Some(s) => { if s.a != 11 or s.b != 4000000003 { return 104 } }
    Option::None => { return 105 }
  }

  ## deque pop_front / pop_back of a multi-payload enum and of `Option(u64)`
  mut de := deque::deque(EN, ptr(ar), 2)
  p4 := deque::push_back(EN, de, EN.B(3, i64(0) - 77))
  p5 := deque::push_back(EN, de, EN.A(6))
  p6 := deque::push_back(EN, de, EN.B(5, 123456789))
  fe := deque::pop_front(EN, de)
  match fe {
    Option::Some(e) => { if enkey(e) != 2923 { return 106 } }
    Option::None => { return 107 }
  }
  be := deque::pop_back(EN, de)
  match be {
    Option::Some(e) => { if enkey(e) != 123461789 { return 108 } }
    Option::None => { return 109 }
  }
  mut dq := deque::deque(Option(u64), ptr(ar), 2)
  p7 := deque::push_back(Option(u64), dq, Option(u64).Some(20))
  p8 := deque::push_back(Option(u64), dq, Option(u64).None)
  p9 := deque::push_back(Option(u64), dq, Option(u64).Some(30))
  fo := deque::pop_front(Option(u64), dq)
  match fo {
    Option::Some(x) => { if optkey(x) != 41 { return 110 } }
    Option::None => { return 111 }
  }
  bo := deque::pop_back(Option(u64), dq)
  match bo {
    Option::Some(x) => { if optkey(x) != 61 { return 112 } }
    Option::None => { return 113 }
  }

  ## hashmap get at `V = Option(u64)` and `V = EN` (`v := deref(val_at(K, V, …))` in the instance)
  mut m := hashmap::new(u64, Option(u64), ptr(ar))
  q0 := hashmap::insert(u64, Option(u64), ptr(m), ar, 5, Option(u64).Some(8))
  mo := hashmap::get(u64, Option(u64), ptr(m), ar, 5)
  match mo {
    Option::Some(x) => { if optkey(x) != 17 { return 114 } }
    Option::None => { return 115 }
  }
  mut me := hashmap::new(u64, EN, ptr(ar))
  q1 := hashmap::insert(u64, EN, ptr(me), ar, 9, EN.B(2, 44))
  meo := hashmap::get(u64, EN, ptr(me), ar, 9)
  match meo {
    Option::Some(e) => { if enkey(e) != 2044 { return 116 } }
    Option::None => { return 117 }
  }

  ## past the initial capacity, so `rehash` moves every value (`v := deref(ovp)`, `ovp` a
  ## `bitcast(ptr(mut V), …)` local in the instance)
  mut i : u64 = 0
  while i < 20 {
    q2 := hashmap::insert(u64, Option(u64), ptr(m), ar, 100 + i, Option(u64).Some(i * 3))
    q3 := hashmap::insert(u64, EN, ptr(me), ar, 100 + i, EN.B(u8(i), i64(i) * 7))
    i += 1
  }
  i = 0
  while i < 20 {
    ro := hashmap::get(u64, Option(u64), ptr(m), ar, 100 + i)
    match ro {
      Option::Some(x) => { if optkey(x) != i * 6 + 1 { return 118 } }
      Option::None => { return 119 }
    }
    re := hashmap::get(u64, EN, ptr(me), ar, 100 + i)
    match re {
      Option::Some(e) => { if enkey(e) != i64(i) * 1007 { return 120 } }
      Option::None => { return 121 }
    }
    i += 1
  }
  42
}
