## #1421 — `for x in alloc::vec::iter(T, …)`, the `Slice(T)`-returning call written DIRECTLY as the
## loop's iterable, steps and loads one `T` per element (Types §6.4: stride is `T`'s size; Control Flow
## §6), for u16, u8 and u32, exactly as the same view bound to a local first does. Each check returns
## its own code; 42 is a pass.
## Parent `b94bf1d2` of #1422 (x86_64, omen): built, and ran to 1 (the u16 direct loop) from both
## build-then-run and `alatyr run`.
sys_mmap := @abi(syscall) fn(
  num : usize,
  addr : usize,
  len : usize,
  prot : usize,
  flags : usize,
  fd : usize,
  off : usize,
) -> isize

main := fn() -> u64 {
  r := unchecked (sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0))
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  mut h := alloc::vec::new(u16, ptr(ar))
  h0 := h.push(30)
  h1 := h.push(5)
  mut sum : u64 = 0
  unchecked {
    for x in alloc::vec::iter(u16, ptr(h)) {
      sum = sum + u64(x)
    }
  }
  if sum != 35 {
    return 1
  }
  mut v8 := alloc::vec::new(u8, ptr(ar))
  b0 := v8.push(30)
  b1 := v8.push(5)
  b2 := v8.push(7)
  mut s8 : u64 = 0
  for x in alloc::vec::iter(u8, ptr(v8)) {
    s8 = s8 * 100 + u64(x)
  }
  if s8 != 300507 {
    return 2
  }
  mut v32 := alloc::vec::new(u32, ptr(ar))
  w0 := v32.push(30)
  w1 := v32.push(5)
  w2 := v32.push(7)
  mut s32 : u64 = 0
  for x in alloc::vec::iter(u32, ptr(v32)) {
    s32 = s32 * 100 + u64(x)
  }
  if s32 != 300507 {
    return 3
  }
  it : Slice(u16) = alloc::vec::iter(u16, ptr(h))
  mut sb : u64 = 0
  unchecked {
    for x in it {
      sb = sb + u64(x)
    }
  }
  if sb != 35 {
    return 4
  }
  42
}
## expect: run 42
