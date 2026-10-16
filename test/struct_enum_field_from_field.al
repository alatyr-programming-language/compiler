## #958: a struct literal's enum field initialized from another struct's enum field (`Q(c = q.c)`).
## x86_64 fell through to the array branch and stored nothing, so `p.c` read all-zero and matched no
## payload (8); the field now gets the source's words. B(3, 4) -> 34, + 8 = 42.
Col := enum { R(u64), G, B(u64, u64) }
Q := struct { c : Col, z : i64 }
main := fn() -> u64 {
  q := Q(c = Col.B(3, 4), z = 3)
  p := Q(c = q.c, z = 21)
  w : u64 = match p.c { Col.R(v) => v; Col.G => 0; Col.B(m, n) => m * 10 + n }
  w + 8
}
