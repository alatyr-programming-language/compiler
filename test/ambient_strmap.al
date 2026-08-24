## e2e — str-keyed alloc::strmap (byte-slice keys, content hash + bytes_eq) ambiently. "hi"->40,
## "yo"->2, read both, sum 42. Exercises Slice(u8) s[i] BYTE indexing (stride 1) in hash_bytes/bytes_eq.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut m := alloc::strmap::strmap_new(ptr(ar), 16)
  alloc::strmap::strmap_insert(m, bytes("hi"), 40)
  alloc::strmap::strmap_insert(m, bytes("yo"), 2)
  a := alloc::strmap::strmap_get(m, bytes("hi"))
  b := alloc::strmap::strmap_get(m, bytes("yo"))
  match a {
    Option::Some(x) => { match b { Option::Some(y) => { x + y } Option::None => { 100 } } }
    Option::None => { 200 }
  }
}
