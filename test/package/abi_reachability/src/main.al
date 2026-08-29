## The test-only ABI declaration. Its basename deliberately collides with the `@abi(syscall)` the
## production path reaches inside `std::os`, so DCE has to tell the two apart by declaration and not
## by name: this one must be absent from the production artifact (`main__sys_mmap`) while
## `std__os__sys_mmap` is retained.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

pub production_api := fn() -> u64 {
  ## The production call goes through the stdlib's `pub` surface (Modules §3: `std::os::sys_mmap` is
  ## NOT `pub`, and `main` is a sibling of `std`, so naming it directly is a §3 violation — it was one
  ## here until 2026-08-20). `std::os::arena` is `pub` and is the declared owner of that private
  ## `@abi(syscall)`, so the retained-but-private trampoline this fixture is about is reached exactly
  ## as a real program reaches it. `OsArena` is `@owning`, so the region is freed once.
  arena_result := std::os::arena(4096)
  mut out : u64 = 0
  match arena_result {
    Result::Ok(r) => {
      _ := std::os::free(r)
      out = 42
    }
    Result::Err(e) => { panic("abi_reachability: OS arena allocation failed") }
  }
  return out
}

@test("test-only abi remains in dedicated test artifact") fn() {
  neg1 : isize = 0 - 1
  pid := unchecked sys_mmap(9, 0, 4096, 3, 34, bitcast(usize, neg1), 0)
  if pid < 0 { panic("getpid failed") }
}
