## e2e — #980 (IR-36): the source-scan shape the compiler's own src/ is written in. `str_at(p, n)` is a
## raw view of `n` bytes at `p` with no copy (Stdlib appendix §3.6), its call raw (Memory §4.5); `p` is
## a `ptr(u8)` here, which `check` accepts for the appendix's `in p : usize` (#529); its
## address is `p + i`, pointer arithmetic over a one-byte pointee, where a byte offset and an element
## offset are the same address; and two `str` compare equal when their lengths and bytes are (STD-4). The
## shared IR builds all three: the scan below counts by a one-byte view per position, a nested `p + 1 + i`
## skips the first byte, and the word test meets a view that differs only in its last byte, one of equal
## bytes, a shorter one under `!=`, and a view that crosses an IR-built call as a result.
## 3 parens + 2 after the first byte + 1 + 2 + 3 + 2 + 2 = 15, + 27 = 42.
## expect: run 42
parens := fn(p : ptr(u8), n : usize) -> u64 {
  mut k : u64 = 0
  mut i : usize = 0
  while i < n {
    c := unchecked str_at(p + i, 1)
    if c == "(" { k = k + 1 }
    i = i + 1
  }
  k
}

tail_parens := fn(p : ptr(u8), n : usize) -> u64 {
  mut k : u64 = 0
  mut i : usize = 0
  while i + 1 < n {
    if unchecked str_at(p + 1 + i, 1) == "(" { k = k + 1 }
    i = i + 1
  }
  k
}

lexeme := fn(p : ptr(u8), off : usize, len : usize) -> str {
  unchecked str_at(p + off, len)
}

kw := fn(p : ptr(u8), off : usize, len : usize) -> u64 {
  w := lexeme(p, off, len)
  if w == "fm" { return 9 }
  if w == "fn" { return 1 }
  if w != "let" { return 2 }
  3
}

main := fn() -> u64 {
  ## the bytes of "(a(b)fn let(c"
  b : [u8; 13] = [40, 97, 40, 98, 41, 102, 110, 32, 108, 101, 116, 40, 99]
  p := ptr(b[0])
  n : usize = 13
  total := parens(p, n) + tail_parens(p, n) + kw(p, 5, 2) + kw(p, 4, 2) + kw(p, 8, 3) + kw(p, 5, 1)
  total + kw(p, 5, 3) + 27
}
