## Package-shaped regression for Codegen §3.5 / CG-10 and the codec-library
## inline aggregate/bytes reports. The expected process exit code is 42.
## Keep the fixture self-contained: package builds intentionally do not ambiently
## inject bare `Slice` modules, so this is the same two-word library view shape.
Slice := fn(T : type) -> type {
  struct { ptr : ptr(T), len : usize }
}

@inline head := fn(s : Slice(u8)) -> u8 {
  s[0]
}

main := fn() -> u64 {
  mut buf : [u8; 2] = [42, 0]
  s := Slice(u8)(ptr = ptr(buf[0]), len = 2)
  got_local := u64(head(s))
  got_bytes := u64(head(bytes("*")))
  if got_local != 42 { return 1 }
  if got_bytes != 42 { return 2 }
  return 42
}
