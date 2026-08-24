## e2e — struct-VALUE HashMap through the ambient path. `HashMap(u64, Pt)` with the VALUE a
## 2-field struct: `hashmap_get` returns `Option(Pt)` (a generic enum whose payload is the
## callee's own type-param V=Pt). The caller must size/stage/match the `Some(Pt)` payload as the
## concrete 2-word struct — the generic-enum-return substitution on the result binding. Insert
## 7 -> Pt{40,2}, read back, sum the fields -> 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Pt := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := alloc::hashmap::new(u64, Pt, ptr(ar))
  alloc::hashmap::hashmap_insert(u64, Pt, ptr(m), ar, 7, Pt(x = 40, y = 2)).expect("insert")
  rr := alloc::hashmap::hashmap_get(u64, Pt, ptr(m), ar, 7)
  match rr {
    Option::Some(v) => { v.x + v.y }
    Option::None => { 1 }
  }
}
