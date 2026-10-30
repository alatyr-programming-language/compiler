## #1237 — `deref(p) = f()` with `f` returning a multi-word aggregate stores only the first word.
## Due 42: the store must write all three words, so `q.a + q.b` is 40 + 2.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
P := struct { a : u64, b : u64, c : u64 }
mk := fn(x : u64) -> P { P(a = x, b = 2, c = 3) }
main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  p : ptr(mut P) = unchecked bitcast(ptr(mut P), bitcast(usize, r))
  deref(p) = mk(40)
  q := deref(p)
  q.a + q.b
}
