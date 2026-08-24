## String escapes decode to bytes before the str {ptr,len} value is formed.
main := fn() -> u64 {
  a := "\x00A"
  if a.len != 2 { return 1 }
  if bytes(a)[0] != 0 { return 2 }
  if bytes(a)[1] != 65 { return 3 }
  e := "\xC3\xA9"
  if e.len != 2 { return 4 }
  if bytes(e)[0] != 195 { return 5 }
  if bytes(e)[1] != 169 { return 6 }
  42
}
