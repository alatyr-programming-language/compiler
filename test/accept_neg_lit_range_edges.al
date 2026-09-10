## Types §9.1 (#602) — the OVER-EAGERNESS control for the negative-literal refusal, and the whole
## risk of the change: the signed bound is ASYMMETRIC (`i8` is −128 .. 127), so a rule written from
## the positive half's shape would refuse the very values it must accept. Every lower bound is
## exercised at the bound, in the annotation spelling, the constructor spelling and the
## no-annotation default, and each is asserted by VALUE — the defect this family exists for was an
## accepted program with a wrong one.
##
## `i64` MIN is the sharpest case in the language: its magnitude, 2^63, is not representable as a
## positive value of the same type, so the negation wraps to itself. `-0` is the other edge — its
## mathematical value is zero, which every integer type holds, including the unsigned ones for
## which every OTHER negative literal is out of range.
##
## `- -4`, `-  7` and `- (5)` are the spellings the parser's adjacency guard deliberately leaves as
## `Unchecked(Bin(17, Num(0), …))`; `fmt_neg_lit_adjacency` is where their rendering is pinned, and
## they are here so that their VALUES are pinned on all four backends too.
Gi8 : i8 = -128
Gi64 : i64 = -9223372036854775808
Gdef := -9223372036854775808

f8 := fn(v : i8) -> i64 {
  i64(v)
}

g8 := fn() -> i8 {
  return -128
}

main := fn() -> u64 {
  a : i8 = -128
  b : i16 = -32768
  c : i32 = -2147483648
  d : i64 = -9223372036854775808
  e : isize = -9223372036854775808
  h := -9223372036854775808
  i := -5
  j : i8 = i8(-128)
  k : i16 = i16(-32768)
  l : i32 = i32(-2147483648)
  m : i64 = i64(-9223372036854775808)
  zu : u8 = -0
  zi : i8 = -0
  hx : i8 = -0x80
  us : i16 = -32_768
  nn := - -4
  sp := -  7
  pr := - (5)
  if i64(a) != 0 - 128 { return 1 }
  if i64(b) != 0 - 32768 { return 2 }
  if i64(c) != 0 - 2147483648 { return 3 }
  if d != 0 - 9223372036854775807 - 1 { return 4 }
  if e != 0 - 9223372036854775807 - 1 { return 5 }
  if h != 0 - 9223372036854775807 - 1 { return 6 }
  if i != 0 - 5 { return 7 }
  if i64(j) != 0 - 128 { return 8 }
  if i64(k) != 0 - 32768 { return 9 }
  if i64(l) != 0 - 2147483648 { return 10 }
  if m != 0 - 9223372036854775807 - 1 { return 11 }
  if u64(zu) != 0 { return 12 }
  if i64(zi) != 0 { return 13 }
  if i64(hx) != 0 - 128 { return 14 }
  if i64(us) != 0 - 32768 { return 15 }
  if nn != 4 { return 16 }
  if sp != 0 - 7 { return 17 }
  if pr != 0 - 5 { return 18 }
  if i64(Gi8) != 0 - 128 { return 19 }
  if Gi64 != 0 - 9223372036854775807 - 1 { return 20 }
  if Gdef != 0 - 9223372036854775807 - 1 { return 21 }
  if f8(-128) != 0 - 128 { return 22 }
  if i64(g8()) != 0 - 128 { return 23 }
  return 42
}
