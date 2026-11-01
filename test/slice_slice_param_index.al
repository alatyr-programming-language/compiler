## #1181 — a `Slice(Slice(u8))` parameter's element is the two-word view pair (Types §7), so
## `xs[i].len` reads element i's own length. Expected exit 32 (the issue's third row). The parent read
## the elements at a one-word stride and exited 20.
lens := fn(xs : Slice(Slice(u8))) -> u64 {
  mut n : u64 = 0
  mut i : usize = 0
  while i < xs.len {
    n = n * 10 + u64(xs[i].len)
    i += 1
  }
  n
}

main := fn() -> u64 {
  a : [u8; 3] = [1, 2, 3]
  b : [u8; 2] = [4, 5]
  t : [Slice(u8); 2] = [a[0..3], b[0..2]]
  lens(t[0..2])
}
