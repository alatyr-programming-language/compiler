## focused P1 x86 correctness — structural == / != over local plain-struct array elements.
## The second word must participate, equal values at different addresses must compare equal, and
## dynamic indices / distinct local roots must use the addressed element rather than word 0.
P := struct { x : u64, y : u64 }

main := fn() -> u64 {
  xs : [P; 3] = [P(x = 1, y = 2), P(x = 1, y = 3), P(x = 1, y = 2)]
  ys : [P; 1] = [P(x = 1, y = 2)]
  mut i : usize = 0
  mut j : usize = 1
  mut acc : u64 = 0

  if xs[0] == xs[1] { acc = acc + 1 } else { acc = acc + 2 }  ## word-1 difference -> +2
  if xs[0] != xs[1] { acc = acc + 4 }                          ## != -> +4
  if xs[0] == xs[2] { acc = acc + 8 }                          ## equal value, different address -> +8
  i = 0
  j = 1
  if xs[i] != xs[j] { acc = acc + 16 }                         ## dynamic unequal indices -> +16
  if xs[i] == ys[0] { acc = acc + 12 }                         ## equal values, different roots -> +12
  return acc
}
