## Repro for the generic identity return ABI: `str` is a by-value {ptr, len} view.
## Both the bound and direct forms must preserve the byte pointer and byte length.
id := fn(T : type, x : T) -> T { return x }

main := fn() -> u64 {
  source := "abcd"
  bound := id(str, source)
  if bound.len != 4 { return 38 + bound.len }
  if id(str, source).len != 4 { return 39 + id(str, source).len }
  if unchecked bitcast(usize, bound.ptr) != unchecked bitcast(usize, id(str, source).ptr) { return 40 }
  return 42
}
