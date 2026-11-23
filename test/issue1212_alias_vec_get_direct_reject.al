## e2e / issue #1212 — a DIRECT `match` on `alloc::vec::get` through a type alias is refused at the call,
## naming the construct it refuses.
##
## The issue's second acceptance: the direct form either runs to the right value or is refused with a
## message that names what it refuses. It used to be refused with a message about `.map(f)` /
## `.and_then(f)` / `.map_err(g)`, which the program does not contain. The x86_64 lowering still cannot
## take a generic call's multi-word enum result as a `match` scrutinee, so it refuses with a message
## naming a direct `match` on a generic call. A valid program: the bound form is
## `test/issue1212_alias_vec_get.al`.
##
## NON-VACUOUS: at `cdcecb5c` (omen, native x86_64) the direct form answered 3 (a wrong value).
Thread := std::thread::Thread

main := fn() -> u64 {
  match std::os::arena(65536) {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      mut v := alloc::vec::with_capacity(Thread, ptr(mut ar), 4)
      r0 := alloc::vec::push(Thread, v, Thread(ctid_addr = 1, stack_base = 2, stack_len = 3))
      match alloc::vec::get(Thread, ptr(v), 0) {
        Some(t) => { if u64(t.stack_len) != 3 { return 3 } }
        None => { return 2 }
      }
      42
    }
    Err(_) => { 1 }
  }
}
## expect: reject "truncates the scrutinee to its first word"
