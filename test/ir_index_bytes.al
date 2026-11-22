## e2e — #1865: `bytes(x)[i]`, byte `i` of the `[u8]` view of the `str` `x` (Stdlib appendix §3.6), is
## built by the shared IR as an index of `x`'s own `{ptr, len}` pair at the `u8` element: `bound i, len`
## (Types §6.4), and no code-point guard, which is a `str` index's (§3.6). The view's base is a `str`
## parameter (`at`), a literal (`lit`), and `str_at(p, 1)`, the byte at an address — the shape the
## compiler's own src/ spells most (`raw`). `mid` reads byte 1 of "é" (0xC3 0xA9): a `str` index there
## traps, a `[u8]` index answers 0xA9 = 169.
## 42 = '*' (42); `lit` 'b' (98) - 97 = 1, `raw` '(' (40) - 39 = 1, so the sum is 44 - 2.
## expect: run 42
at := fn(s : str, i : usize) -> u8 { bytes(s)[i] }
lit := fn(i : usize) -> u8 { bytes("abc")[i] }
raw := fn(p : ptr(u8)) -> u8 { unchecked bytes(str_at(p, 1))[0] }
mid := fn(s : str) -> u8 { bytes(s)[1] }

main := fn() -> u64 {
  b : [u8; 2] = [41, 40]
  p := ptr(b[1])
  if mid("é") != 169 { return 1 }
  u64(at("x*y", 1)) + u64(lit(1)) - 97 + u64(raw(p)) - 39 - 2
}
