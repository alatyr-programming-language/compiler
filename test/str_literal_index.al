## e2e (#405) — indexing a str LITERAL directly, `"abc"[i]`. `str` IS `[u8]` (Types §7,
## appendix 160 §3.6), so the element is one BYTE at that byte offset, not a word. The literal
## has no frame home, so lower used to fall through every recognizer to the generic element
## address (frame slot 0 + i*8) and load a WORD: `u64("abc"[2])` ran to 5 instead of 99, a
## SILENT WRONG VALUE. Each check has its own failure code from 100 so a regression names the
## exact form; the neighbouring bytes are distinct and non-zero, so a constant-0 or a shifted
## index cannot pass. Returns 42 iff every form is exact.
main := fn() -> u64 {
  ## the reported form: a constant index into a literal
  if u64("abc"[2]) != 99 { return 100 }
  ## the first byte, so a slot-0 read cannot be mistaken for a correct answer
  if u64("abc"[0]) != 97 { return 101 }
  if u64("abc"[1]) != 98 { return 102 }
  ## a RUNTIME index into a literal (the index is lowered, not folded)
  i := 1
  if u64("abc"[i]) != 98 { return 103 }
  ## a literal index in ARGUMENT position and in a BINDING
  b := "abc"[2]
  if u64(b) != 99 { return 104 }
  if same(u64("abc"[0])) != 97 { return 105 }
  ## an arithmetic combination that is NOT commutative, so a swap of the two reads is visible
  if u64("abc"[2]) - u64("abc"[0]) != 2 { return 106 }
  ## a literal index used as the INDEX of another literal index
  if u64("abc"[usize("ab"[1]) - 97]) != 98 { return 107 }
  ## byte, not code point: "\xc3\xa9" is the two UTF-8 bytes of U+00E9
  if u64("\xc3\xa9"[0]) != 195 { return 108 }
  if u64("\xc3\xa9"[1]) != 169 { return 109 }
  ## an escape inside the literal still indexes the DECODED bytes
  if u64("a\nb"[1]) != 10 { return 110 }
  ## the controls named by the report must stay exact
  s := "abc"
  if u64(s[2]) != 99 { return 111 }
  if u64(bytes("abc")[2]) != 99 { return 112 }
  ## an `unchecked` REGION drops the bound check but not the value
  if unchecked { u64("abc"[2]) } != 99 { return 113 }
  return 42
}

same := fn(v : u64) -> u64 {
  v
}
