## e2e — struct-KEY HashMap through the ambient path. `HashMap(Pt, u64)` with Pt a 2-field
## struct: exercises struct type-arg mangling for a 2-type-param generic + `hash(k)`/`eq(a,b)`
## over struct LOCALS (derive over a struct key). Insert Pt{3,4} -> 42, read back -> 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Pt := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := alloc::hashmap::new(Pt, u64, ptr(ar))
  k := Pt(x = 3, y = 4)
  alloc::hashmap::hashmap_insert(Pt, u64, ptr(m), ar, k, 42).expect("insert")
  rr := alloc::hashmap::hashmap_get(Pt, u64, ptr(m), ar, k)
  match rr {
    Option::Some(v) => { u64(v) }
    Option::None => { 1 }
  }
}
