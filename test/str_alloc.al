## e2e — allocating base str utilities in `alloc::string` (each returns a NEW owned String over the
## arena): `to_ascii_lowercase`, `to_ascii_uppercase`, `replace`, and `repeat`. Verified by reading each result
## back as a borrowed `str` view (`as_str`, the owned→borrowed bridge) and byte-comparing it (`==`) to
## the expected literal. Raw `@abi(syscall)` mmap arena so the program is self-contained. Returns 42
## iff all three are exact.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
strm := alloc::string

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 262144, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 262144)

  lo := strm::to_ascii_lowercase(ptr(ar), "Hello, World")
  up := strm::to_ascii_uppercase(ptr(ar), "Hello, World")
  rp := strm::replace(ptr(ar), "a-b-c-d", "-", "::")
  rep := strm::repeat(ptr(ar), "xy", 3)

  slo := strm::as_str(ptr(lo))
  sup := strm::as_str(ptr(up))
  srp := strm::as_str(ptr(rp))
  srep := strm::as_str(ptr(rep))

  if slo == "hello, world" and sup == "HELLO, WORLD" and srp == "a::b::c::d" and srep == "xyxyxy" {
    return 42
  }
  return 7
}
