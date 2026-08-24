## e2e (Shape B — CONTAINER-element aggregate FIELD update, end to end). A `Vec(Rec)` of a 2-word
## struct. The read surface `at` returns `T` BY VALUE (a scoped copy), so the element-field update
## idiom is read-modify-write: `mut e := v.at(i); e.a = …; e.b = …; v.set(i, e)` — the whole-element
## store `set`/`index_set` (`deref(elem) = x`, a struct `DerefAssign`) delivers ALL of the struct's
## words. Also a whole-element overwrite `set(v, 0, Rec(…))`. Reads every field back. This confirms the
## container multi-word-struct element write path is sound (the same `deref(ptr) = <struct>` store the
## omap_struct_value test exercises through the generic map). 2 + 2 + 30 + 8 = 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
Rec := struct { a : u64, b : u64 }
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(Rec, ptr(ar))
  alloc::vec::push(Rec, v, Rec(a = 1, b = 2)).expect("p")
  alloc::vec::push(Rec, v, Rec(a = 3, b = 4)).expect("p")
  mut e := alloc::vec::at(Rec, ptr(v), 1)     ## scoped value copy of element 1
  e.a = 30
  e.b = 8
  alloc::vec::set(Rec, v, 1, e)               ## whole-element store back (2-word struct)
  alloc::vec::set(Rec, v, 0, Rec(a = 2, b = 2))
  x := alloc::vec::at(Rec, ptr(v), 0)
  y := alloc::vec::at(Rec, ptr(v), 1)
  return x.a + x.b + y.a + y.b
}
