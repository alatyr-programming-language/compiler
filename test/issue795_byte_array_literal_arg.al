## Issue #795 — an ARRAY LITERAL passed straight to a byte-element fixed-array parameter
## `[u8|i8; N]`. The callee reads such a parameter as N packed bytes through its pointer, but the
## literal argument was staged one WORD per element, so `xs[1]` read the second byte of element 0:
## the parent built this program and `first([1, 7])` answered 0. Each call below passes a literal:
## a register argument, a literal wider than one word (10 bytes) between two scalars, a literal in
## the seventh (stack) argument position, a signed `i8` literal, and runtime-valued elements. The
## parts add up to the fixture convention's 42.
first := fn(xs : [u8; 2]) -> u64 { return u64(xs[1]) }
wide := fn(k : u64, xs : [u8; 10], j : u64) -> u64 { return u64(xs[9]) + u64(xs[0]) + k + j }
seventh := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, xs : [u8; 2]) -> u64 {
  return a + b + c + d + e + f + u64(xs[1])
}
sgn := fn(xs : [i8; 2]) -> u64 {
  if xs[0] < 0 { return u64(xs[1]) }
  return 100
}
main := fn() -> u64 {
  mut total : u64 = first([1, 7])
  total += wide(1, [2, 0, 0, 0, 0, 0, 0, 0, 0, 10], 3)
  total += seventh(1, 1, 1, 1, 1, 1, [0, 5])
  total += sgn([-3, 4])
  n : u8 = 2
  total += first([n, n + 2])
  return total
}
