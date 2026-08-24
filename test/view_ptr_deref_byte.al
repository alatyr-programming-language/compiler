## e2e (Types §9.4 / §6.4 — `deref` through the DATA POINTER of a view reads ONE BYTE).
## A `str` is `{ptr : ptr(u8), len}` and `str` IS `[u8]` (appendix 160 §3.5), so `q := s.ptr` is a
## `ptr(u8)` and `deref(q)` must load a single byte. The slot carried no pointee type (`.ptr` binds an
## untyped scalar — the inference records only BUILT-IN NUMERIC names), so `deref_pointee_bytes` fell
## to its `movq` default and `deref(q)` returned the first EIGHT bytes of the string as one integer —
## a SILENT MISCOMPILE plus a 7-byte OVER-READ past a short str. It hid behind exit codes:
## `u64(deref(q))` truncates mod 256 back to the right byte, while `if deref(q) != 104` compared the
## full word and took the WRONG branch — the same read disagreeing with itself by position.
## Locks all three view shapes a `.ptr` can come from: a str LITERAL local, a str-returning CALL
## result, and a `bytes(…)` view; the `> 255` test is the one that fails on a word-sized load.
## Value: 104 - 4 = 100 (< 126 — the WASM sweep's WASI `proc_exit` bound).
rd := fn() -> str { return "hello" }

main := fn() -> u64 {
  s := "hello"
  p := s.ptr
  if deref(p) != 104 { return 1 }      ## 'h'; was the word 0x6f6c6c6568
  t := rd()
  q := t.ptr                           ## the CALL-bound str
  if deref(q) != 104 { return 2 }
  v := u64(deref(q))
  if v > 255 { return 3 }              ## a word-sized load fails HERE, where mod-256 cannot hide it
  b := bytes(s)
  w := b.ptr
  if deref(w) != 104 { return 4 }
  return v - 4
}
