## e2e / issue #992 — `alloc::with` reaches through a `match` in both directions.
##
## Memory §5.2.1 (MEM-5): `alloc::with(ar) { … }` makes `ar` the ambient allocator for its whole
## body, lexically, and a call there that omits its allocator parameter is passed `ptr(ar)`. The
## pass that splices the ambient in never walked a `match`. So an `alloc::with` written inside a
## match arm was never seen, and its calls ran with the allocator argument missing:
## "vec_in: allocator out of memory". A `match` inside an `alloc::with` body missed it the same way.
##
## Each check owns a code from 100 up; 42 means all held.
##
## Parent `488186d7` (x86_64, omen): built rc 0, ran to 1 where 42 was due — the trap
## "vec_in: allocator out of memory".
vec := alloc::vec

main := fn() -> u64 {
  match std::os::arena(65536) {
    Result::Ok(m) => {
      mut ar := m.region()
      mut n : u64 = 0
      alloc::with(ar) {
        mut v := vec::new(u64)
        x := v.push(40)
        match x {
          Result::Ok(c) => {
            mut w := vec::new(u64)
            y := w.push(2)
            n = vec::at(u64, ptr(v), 0) + vec::at(u64, ptr(w), 0)
            g := w.free()
          }
          Result::Err(e) => { n = 100 }
        }
        f := v.free()
      }
      fm := std::os::free(m)
      return n
    }
    Result::Err(e) => { return 101 }
  }
}
