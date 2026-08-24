## e2e — `match <qualified generic call>` in NON-TAIL position (payload bound to an outer var, not
## delivered by a direct arm-return). Regression for a bug where `enum_ret_call`/`call_ret_enum_span`
## matched the callee by the RAW span, so a QUALIFIED `alloc::vec::pop(u64,v)` (name "pop" vs the span
## "alloc::vec::pop") went unrecognized as enum-returning → the statement/value match fell to the
## INTEGER path (no payload staging, both arms compared the discriminant to 0) and the bound payload
## read 0. Fixed by matching on the TAIL name. Push 30,42; pop -> Some(42); bind to `last`; return 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  alloc::vec::push(u64, v, 30).expect("p")
  alloc::vec::push(u64, v, 42).expect("p")
  mut last : u64 = 0
  match alloc::vec::pop(u64, v) {
    Option::Some(x) => { last = x }
    Option::None => { last = 100 }
  }
  return last
}
