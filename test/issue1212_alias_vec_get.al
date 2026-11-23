## e2e / issue #1212 — `alloc::vec::get` over a three-word struct named through a TYPE ALIAS keeps
## every field.
##
## Modules §4.1 makes an alias erased: `Thread := std::thread::Thread` names the same type, so
## `vec::get(Thread, …)` is `vec::get(std::thread::Thread, …)` and `Some(t)` carries element `i` whole
## (Stdlib appendix §6). This is the pipeline pilot's spelling (`pilots/pipeline/src/main.al`), the shape
## the issue was rescoped to once #1327/#1340 fixed the unaliased call: two handles pushed, read back by
## index and folded, then one read bound to a local first. `test/issue1212_option_deref_struct.al` holds
## the unaliased `get`/`try_at`/`pop` rows. Each check owns a code from 2 up; 42 means every field arrived.
##
## NON-VACUOUS: at `cdcecb5c` (omen, native x86_64) the alias spelling answered 3 (the folded fields were
## wrong), bound or direct. At `dc9e18e2` the bound form answers 42 on both x86_64 paths; the direct
## `match` is refused at the call (`test/issue1212_alias_vec_get_direct_reject.al`).
Thread := std::thread::Thread

main := fn() -> u64 {
  match std::os::arena(65536) {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      mut v := alloc::vec::with_capacity(Thread, ptr(mut ar), 4)
      r0 := alloc::vec::push(Thread, v, Thread(ctid_addr = 1, stack_base = 2, stack_len = 3))
      r1 := alloc::vec::push(Thread, v, Thread(ctid_addr = 4, stack_base = 5, stack_len = 6))
      mut acc : u64 = 0
      mut i : usize = 0
      while i < 2 {
        o := alloc::vec::get(Thread, ptr(v), i)
        match o {
          Some(t) => { acc = acc * 1000 + u64(t.ctid_addr) * 100 + u64(t.stack_base) * 10 + u64(t.stack_len) }
          None => { return 2 }
        }
        i = i + 1
      }
      if acc != 123456 { return 3 }
      ol := alloc::vec::get(Thread, ptr(v), 1)
      match ol {
        Some(t) => { if u64(t.stack_len) != 6 { return 4 } }
        None => { return 5 }
      }
      42
    }
    Err(_) => { 1 }
  }
}
## expect: run 42
