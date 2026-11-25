- **A range view `u[lo..hi]` over a byte-field struct array starts at element `lo` (#1289).** With
  `Q := struct { a : u8, b : u8 }`, `u[1..3]` scaled its low bound by a word per element, so on x86_64
  `qs[0].a` read 0, `qs[1].b = 9` wrote the wrong element, and `for q in u[1..3]` read zeros.
