## Cross-backend scalar range-slice: `xs[lo..hi]` yields a {ptr,len} view; `s[i]` reads elements
## (stride-aware through the data pointer) and `s.len` is the runtime length. No floats / no writes,
## and a `while` loop (native backends lack `for`) — the minimal shape for the native slice-index
## lowering (x86 already does it). 10 + 20 + 12 = 42.
main := fn() -> u64 {
  xs := [10, 20, 12, 99]
  s := xs[0..3]
  mut acc : u64 = 0
  mut i : usize = 0
  while i < s.len {
    acc = acc + s[i]
    i = i + 1
  }
  return acc
}
