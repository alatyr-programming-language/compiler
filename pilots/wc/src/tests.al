## The counting module's tests: `alatyr test` in this directory.

@test("counts lines, words and bytes") fn() {
  mut k := count::counter()
  count::feed(k, bytes("one two\n  three\n"))
  if k.lines != 2 { panic("lines") }
  if k.words != 3 { panic("words") }
  if k.bytes != 16 { panic("bytes") }
}

@test("a word split across chunks counts once") fn() {
  mut k := count::counter()
  count::feed(k, bytes("ab"))
  count::feed(k, bytes("c d\te"))
  if k.words != 3 { panic("words") }
  if k.bytes != 7 { panic("bytes") }
}

@test("an empty stream counts nothing") fn() {
  mut k := count::counter()
  count::feed(k, bytes(""))
  if k.lines != 0 or k.words != 0 or k.bytes != 0 { panic("counts") }
}
