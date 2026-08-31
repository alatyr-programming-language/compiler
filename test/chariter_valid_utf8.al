## Valid one-, two-, three-, and four-byte UTF-8 sequences must keep their code points and counts.
main := fn() -> u64 {
  s := "Aé€😀"
  if s.len != 10 { return 1 }
  if base::str::codepoint_count(s) != 4 { return 2 }
  mut it : CharIter = CharIter(ptr = s.ptr, len = s.len, pos = 0)
  c0 := unwrap(char, next(it))
  c1 := unwrap(char, next(it))
  c2 := unwrap(char, next(it))
  c3 := unwrap(char, next(it))
  if u32(c0) != 65 or u32(c1) != 233 or u32(c2) != 8364 or u32(c3) != 128512 { return 3 }
  if it.pos != 10 { return 4 }
  42
}
