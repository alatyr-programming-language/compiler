## e2e — stdlib `sort`/`sort_by` CONFORMANCE (appendix §160: an introsort-class algorithm; "a quadratic
## worst case is NON-CONFORMING"). Was a selection sort (O(n²)); now an O(n log n) worst-case heapsort,
## in-place, no allocation. Locks CORRECTNESS on the adversarial REVERSED input (where selection sort
## does maximal work), plus duplicates, edge sizes, the comparator `sort_by` (descending), and a
## large enough reversed slice that the quadratic behavior would be visibly pathological.
sl := base::slice

desc := fn(a : u64, b : u64) -> bool { a > b }

main := fn() -> u64 {
  ## reversed 512 (adversarial for selection sort) — must sort ascending
  a : [u64; 512] = [0; 512]
  mut i : u64 = 0
  while i < 512 {
    a[i] = 511 - i
    i = i + 1
  }
  sa := a[0..512]
  sl::sort(u64, sa)
  i = 0
  while i < 512 {
    if a[i] != i { return 1 }
    i = i + 1
  }

  ## duplicates + already-sorted edge
  b : [u64; 6] = [5, 5, 1, 3, 3, 3]
  sb := b[0..6]
  sl::sort(u64, sb)
  if b[0] != 1 or b[1] != 3 or b[2] != 3 or b[3] != 3 or b[4] != 5 or b[5] != 5 { return 2 }

  ## single + empty edge (must not touch memory)
  c : [u64; 1] = [7]
  sc := c[0..1]
  sl::sort(u64, sc)
  if c[0] != 7 { return 3 }

  ## sort_by descending via comparator fn value
  d : [u64; 5] = [3, 1, 4, 1, 5]
  sd := d[0..5]
  sl::sort_by(u64, sd, desc)
  if d[0] != 5 or d[1] != 4 or d[2] != 3 or d[3] != 1 or d[4] != 1 { return 4 }

  ## A LARGER reversed slice — 20000 elements: heapsort ~260k compares (fast); a selection sort would
  ## do ~200M compares here (seconds), the quadratic behavior this conformance forbids.
  e : [u64; 20000] = [0; 20000]
  i = 0
  while i < 20000 {
    e[i] = 19999 - i
    i = i + 1
  }
  se := e[0..20000]
  sl::sort(u64, se)
  i = 0
  while i < 20000 {
    if e[i] != i { return 5 }
    i = i + 1
  }

  42
}