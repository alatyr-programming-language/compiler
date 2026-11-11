## e2e / issue #1287 — `for x in xs` over a fixed-array PARAMETER `xs : [T; N]` yields its elements in order.
##
## A fixed-array parameter's slot holds the caller's element-0 pointer, and its length is the static N of
## its type: it has no `{ptr, len}` block and no length word. The x86_64 loop read it as a `Slice(T)`
## parameter: it dereferenced the elements once more (a word element segfaulted) and took its bound from
## a frame word it does not own (a struct element trapped). A `str` element was read as one word, so
## `[str; 2]` yielded the pointer words of two strings (exit 12 where 32 is due).
##
## Each element kind owns a code from 100 up; 42 means all held.
##
## Parent `5dc59f62` (x86_64, omen): see the PR for the exit it ran to.
P := struct { a : u64, b : u64 }
E := enum { A(u64), B(u64, u64) }

lens := fn(xs : [str; 2]) -> u64 {
  mut n : u64 = 0
  for s in xs { n = n * 10 + u64(s.len) }
  n
}

words := fn(xs : [u64; 4]) -> u64 {
  mut n : u64 = 0
  for x in xs {
    if x == 2 { continue }
    if x == 4 { break }
    n = n * 10 + x
  }
  n
}

structs := fn(xs : [P; 2]) -> u64 {
  mut n : u64 = 0
  for p in xs { n = n * 10 + p.b }
  n
}

enums := fn(xs : [E; 3]) -> u64 {
  mut n : u64 = 0
  for e in xs {
    match e {
      E::A(x) => { n = n * 10 + x }
      E::B(x, y) => { n = n * 10 + x + y }
    }
  }
  n
}

bytes_u := fn(xs : [u8; 3]) -> u64 {
  mut n : u64 = 0
  for x in xs { n = n * 10 + u64(x) }
  n
}

bytes_i := fn(xs : [i8; 3]) -> i64 {
  mut n : i64 = 0
  for x in xs { n = n * 10 + i64(x) }
  n
}

floats := fn(xs : [f64; 3]) -> f64 {
  mut n : f64 = 0.0
  for x in xs { n = n * 10.0 + x }
  n
}

main := fn() -> u64 {
  ts : [str; 2] = ["abc", "de"]
  if lens(ts) != 32 { return 100 }
  tw : [u64; 4] = [1, 2, 3, 4]
  if words(tw) != 13 { return 101 }
  tp : [P; 2] = [P(a = 1, b = 2), P(a = 3, b = 4)]
  if structs(tp) != 24 { return 102 }
  te : [E; 3] = [E.A(1), E.B(1, 1), E.A(3)]
  if enums(te) != 123 { return 103 }
  tu : [u8; 3] = [1, 2, 3]
  if bytes_u(tu) != 123 { return 104 }
  ti : [i8; 3] = [1, -2, 3]
  if bytes_i(ti) != 83 { return 105 }
  tf : [f64; 3] = [1.0, 2.0, 3.0]
  if floats(tf) != 123.0 { return 106 }
  42
}
## expect: run 42
