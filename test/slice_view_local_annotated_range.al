## #1180 review — a range slice of an ANNOTATED struct-element view LOCAL, `ys : Slice(P) = t[0..3]`,
## is a view of the local's elements (Control Flow §5.4). The local holds the {data, len} pair itself;
## only a `Slice(T)` PARAMETER holds a pointer to the caller's pair (`SlotEntry.is_param`, #1182). The
## first #1180 head took any `name : Slice(T)` for a parameter and loaded once more from the local's
## data pointer: the first two checks went from 46 on the parent to SIGSEGV (139). Each check returns
## its own code; 42 is a pass.
P := struct { a : u64, b : u64 }

sum_b := fn(xs : Slice(P)) -> u64 {
  mut n : u64 = 0
  for p in xs {
    n = n * 10 + p.b
  }
  n
}

main := fn() -> u64 {
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  ys : Slice(P) = t[0..3]
  ## a range of the annotated local, bound and iterated
  zs := ys[1..3]
  if zs.len != 2 {
    return 1
  }
  mut n : u64 = 0
  for p in zs {
    n = n * 10 + p.b
  }
  if n != 46 {
    return 2
  }
  ## the same range passed on to a parameter
  if sum_b(ys[1..3]) != 46 {
    return 3
  }
  ## an element read through the range
  if zs[1].a != 5 {
    return 4
  }
  42
}
## expect: run 42
