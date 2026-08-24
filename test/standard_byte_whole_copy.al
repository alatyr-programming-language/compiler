## CLAYOUT S3(c) — the two whole-value copies that must NOT change, measured beside the ones that
## did. Both are the pre-existing WORD copy, and both are correct for the same reason (audit §5's
## staging principle): the two layouts coincide, so the word copy IS the byte copy.
##
##   `cp := o`      copies the byte-layout ROOT itself. Source and destination are the same type, so
##                  the destination is read at exactly the offsets the source was written at, and a
##                  word-wise copy of `struct_words` words moves the §6.1 image unchanged.
##   `wc := w.inner` copies a WORD-GRANULAR child (`std_struct_is_word_granular`): every field is 8
##                  bytes wide and 8-aligned, so its §6.1 offsets ARE its word offsets times 8. This is
##                  the control the copier must not capture — it keeps its byte-identical emission.
##
## MEASURED exit code (x86_64 / aarch64 qemu / riscv64 qemu / wasm wasmtime), 42 = correct:
##   base 04b221d       42 / 42 / 42 / 42
##   S3(c)              42 / 42 / 42 / 42   (unchanged, which is the point of the fixture)
Leaf   := struct { a : u16, b : u16 }
Word   := struct { x : u64, y : u64 }
Outer  := struct { data : [u8; 8], inner : Leaf }
Wouter := struct { data : [u8; 8], inner : Word }

main := fn() -> u64 {
  mut o := Outer(data = [1, 2, 3, 4, 5, 6, 7, 8], inner = Leaf(a = 20, b = 22))
  cp := o
  if u64(cp.data[0]) != 1 { return 1 }
  if u64(cp.data[7]) != 8 { return 2 }
  if u64(cp.inner.a) != 20 { return 3 }
  if u64(cp.inner.b) != 22 { return 4 }

  mut w := Wouter(data = [9, 8, 7, 6, 5, 4, 3, 2], inner = Word(x = 24, y = 26))
  wc := w.inner
  if wc.x != 24 { return 5 }
  if wc.y != 26 { return 6 }

  ## the sources survive their own copies
  if u64(o.inner.b) != 22 { return 7 }
  if w.inner.y != 26 { return 8 }
  ## and the copies survive each other
  if u64(cp.inner.b) != 22 { return 9 }
  if wc.x != 24 { return 10 }
  42
}
