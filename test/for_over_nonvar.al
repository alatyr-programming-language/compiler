## e2e (for-over-iterable where the iterable is a NON-VAR expression — `for x in <Slice(…)/f()>`).
## The iterable `for` desugar required a Var (`for x in s`); a call/struct-lit iterable
## (`for x in Slice(u64)(…)`, `for x in mk()`) re-read garbage → the loop never ran. Now a non-var
## iterable is MATERIALIZED ONCE into a hidden {ptr,len} temp (reserved by collect_slots at
## slot_of(x)+2..+3) via emit_arm_val_store (a `Slice(…)` StructLit → emit_struct_assign; a str-view
## → emit_str_pair), then the counted loop reads that temp like a by-value slice. Word (u64) elements.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut u64), bitcast(usize, r))
  deref(bp) = 10
  p1 : ptr(mut u64) = unchecked bitcast(ptr(mut u64), bitcast(usize, bp) + 8)
  deref(p1) = 20
  p2 : ptr(mut u64) = unchecked bitcast(ptr(mut u64), bitcast(usize, bp) + 16)
  deref(p2) = 12
  mut s : u64 = 0
  ## the iterable is a Slice CONSTRUCTION (non-var) — materialized once, then iterated
  for x in Slice(u64)(ptr = bp, len = 3) { s = s + x }
  s
}
