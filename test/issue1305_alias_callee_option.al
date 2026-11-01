## #1305 — a call through a MODULE ALIAS (`amap := alloc::map`, then `amap::get(m, 5)`) to a function
## returning a two-word `Option(u64)`. The binding of its result was typed from a different, same-arity
## `get` whose `Option(ptr(T))` return is one niche-folded word, so the match read the discriminant as the
## payload: `x` was 1 for a stored 9. The fully qualified call and an aliased call to a function of
## another name are the controls. Exits 42.
amap := alloc::map
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 1048576, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 1048576)
  m := amap::map_new(ptr(ar), 64)
  amap::insert(m, 5, 9)
  amap::insert(m, 36, 10)
  o := amap::get(m, 5)
  match o {
    Option::Some(x) => { if x != 9 { return 10 } }
    Option::None => { return 11 }
  }
  q := amap::get(m, 36)
  match q {
    Option::Some(x) => { if x != 10 { return 12 } }
    Option::None => { return 13 }
  }
  n := amap::get(m, 7)
  match n {
    Option::Some(x) => { return 14 }
    Option::None => {}
  }
  f := alloc::map::get(m, 5)
  match f {
    Option::Some(x) => { if x != 9 { return 15 } }
    Option::None => { return 16 }
  }
  if not amap::contains(m, 36) { return 17 }
  42
}
## expect: run 42
