## Issue #304 — an annotated Slice(T) parameter must enforce T at an element store.
write := fn(in out s : Slice(u64)) {
  s[0] = "text"
}

main := fn() -> u64 {
  mut xs : [u64; 2] = [1, 2]
  s := xs[0..2]
  write(s)
  0
}
