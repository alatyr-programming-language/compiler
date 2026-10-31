## e2e / issue #1256 — a generic call returning its type parameter, passed straight as an argument.
##
## `mk(S1, x)` and `vec::at(S1, ptr(v), i)` return `T`. A struct or enum parameter is by reference, so
## the argument must be a block holding the returned words. The argument lowering asked only whether
## the DECLARED return (`T`) is a struct or enum, answered no, and pushed the first returned word as
## the block pointer: the callee dereferenced a field value.
##
## Covered: one-, two- and nine-word (hidden result pointer) structs, an enum with a payload, an
## `Option(u64)`, two such calls in one argument list (distinct blocks), and `vec::at` over a struct
## and an enum. Each check owns a code from 100 up; 42 means every value arrived whole.
##
## Parent `c5fc685d` (x86_64, omen): built rc 0, ran to SIGSEGV (139) where 42 was due.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
S1 := struct { a : u64 }
S2 := struct { a : u64, b : u64 }
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
E := enum { C(u64), A(u64, u64), N }

mk := fn(T : type, x : T) -> T { x }

same1 := fn(x : S1, y : S1) -> bool { x.a == y.a }
sum2 := fn(x : S2) -> u64 { x.a * 10 + x.b }
sum9 := fn(x : S9) -> u64 { x.a + x.b + x.c + x.d + x.e + x.f + x.g + x.h + x.i * 100 }
code := fn(e : E) -> u64 {
  match e {
    E.C(k) => { 1000 + k }
    E.A(x, y) => { 2000 + x * 10 + y }
    E.N => { 3000 }
  }
}
opt := fn(o : Option(u64)) -> u64 {
  match o {
    Option::Some(k) => { k }
    Option::None => { 99 }
  }
}

main := fn() -> u64 {
  if not same1(mk(S1, S1(a = 7)), S1(a = 7)) { return 100 }
  if not same1(mk(S1, S1(a = 8)), mk(S1, S1(a = 8))) { return 101 }
  if same1(mk(S1, S1(a = 8)), mk(S1, S1(a = 9))) { return 102 }
  if sum2(mk(S2, S2(a = 4, b = 2))) != 42 { return 103 }
  if sum9(mk(S9, S9(a = 1, b = 1, c = 1, d = 1, e = 1, f = 1, g = 1, h = 1, i = 5))) != 508 { return 104 }
  if code(mk(E, E.A(7, 3))) != 2073 { return 105 }
  if code(mk(E, E.N)) != 3000 { return 106 }
  if opt(mk(Option(u64), Option(u64).Some(41))) != 41 { return 107 }
  if opt(mk(Option(u64), Option(u64).None)) != 99 { return 108 }
  ## the bound form of the `Option(u64)` instance: on the parent it returned the discriminant alone, and
  ## the payload read back was stale (10 in the review's p5 probe)
  ob := mk(Option(u64), Option(u64).Some(41))
  if opt(ob) != 41 { return 109 }

  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  mut v := vec::new(S1, ptr(ar))
  x0 := vec::push(S1, v, S1(a = 7))
  x1 := vec::push(S1, v, S1(a = 9))
  if not same1(vec::at(S1, ptr(v), 0), S1(a = 7)) { return 110 }
  if not same1(vec::at(S1, ptr(v), 1), S1(a = 9)) { return 111 }
  mut w := vec::new(E, ptr(ar))
  y0 := vec::push(E, w, E.C(40))
  y1 := vec::push(E, w, E.A(7, 3))
  if code(vec::at(E, ptr(w), 0)) != 1040 { return 112 }
  if code(vec::at(E, ptr(w), 1)) != 2073 { return 113 }
  mut u := vec::new(Option(u64), ptr(ar))
  z0 := vec::push(Option(u64), u, Option(u64).Some(41))
  zb := vec::at(Option(u64), ptr(u), 0)
  if opt(zb) != 41 { return 114 }
  if opt(vec::at(Option(u64), ptr(u), 0)) != 41 { return 115 }
  vec::free(Option(u64), u)
  vec::free(S1, v)
  vec::free(E, w)
  42
}
