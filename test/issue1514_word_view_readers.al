## #1514 / #1559 — REGRESSION GUARD for PR #1564's refusal: a range slice over a word-layout `u16`
## array (`a16 : [u16; 3]`, one word per element on x86_64) whose every reader steps the word the array
## really has must keep building and answering right. x86_64 refuses such a view only where a reader
## steps `u16`'s own size (test/issue1514_word_array_range_slice.al); each shape below answered right
## on main `0c55e3e4` and must not be refused: a view stored into a `Slice(u16)` struct field by
## assignment (`h.f = s`, `o.a.f = s`, `hs[1].f = s`) as `H(f = s)` always could; a re-slice of the
## local view (`t := s[1..3]`, `for x in s[1..3]`, `s[1..3][0]`, `H(f = s[1..3])`) read like a copy;
## a re-slice handed to a `.len`-only or generic callee; and recursive, mutually recursive and long
## call chains whose callees only read `.len` or re-slice the parameter for a `.len`-only call.
##
## Each check owns a code from 1 up; 42 means all held. Parent `0c55e3e4` (x86_64, omen): run 42.
## aarch64/riscv64 trap (133) and wasm traps (134) at the first range-slice binding's fail-loud stub
## (#1288), `reslice` running first.
H := struct { f : Slice(u16) }
O := struct { a : H, k : u64 }

## R1 — the view stored into a struct field by assignment, then indexed through the field
field_store := fn() -> u64 {
  a16 : [u16; 3] = [1000, 2000, 3000]
  z : [u16; 3] = [1, 2, 3]
  mut h := H(f = z[0..3])
  s := a16[0..3]
  h.f = s
  if u64(h.f[1]) != 2000 { return 1 }
  if h.f.len != 3 { return 2 }
  0
}

## R1 — a longer field path, and an array element's field
field_path_store := fn() -> u64 {
  a16 : [u16; 3] = [1000, 2000, 3000]
  z : [u16; 3] = [1, 2, 3]
  mut o := O(a = H(f = z[0..3]), k = 5)
  s := a16[0..3]
  o.a.f = s
  if u64(o.a.f[2]) != 3000 { return 3 }
  mut hs : [H; 2] = [H(f = z[0..3]), H(f = z[0..3])]
  hs[1].f = s
  h1 := hs[1]
  if u64(h1.f[1]) != 2000 { return 4 }
  0
}

## R2 — a re-slice of the local view, indexed, measured and iterated; and annotated
reslice := fn() -> u64 {
  a16 : [u16; 3] = [1000, 2000, 3000]
  s := a16[0..3]
  t := s[1..3]
  if u64(t[0]) != 2000 { return 5 }
  if t.len != 2 { return 6 }
  mut n : u64 = 0
  for x in t { n = n * 10 + u64(x) }
  if n != 2000 * 10 + 3000 { return 7 }
  u : Slice(u16) = s[1..3]
  if u64(u[1]) != 3000 { return 8 }
  mut m : u64 = 0
  for x in s[1..3] { m = m + u64(x) }
  if m != 5000 { return 9 }
  if u64(s[1..3][0]) != 2000 or s[1..3].len != 2 { return 10 }
  h := H(f = s[1..3])
  if u64(h.f[0]) != 2000 { return 11 }
  0
}

len16 := fn(s : Slice(u16)) -> usize { s.len }
readw := fn(T : type, s : Slice(T), i : usize) -> T { v := s[i]  v }

## R2 — a re-slice handed to a `.len`-only callee and to a generic one
reslice_args := fn() -> u64 {
  a16 : [u16; 3] = [1000, 2000, 3000]
  s := a16[0..3]
  if len16(s[1..3]) != 2 { return 12 }
  if u64(readw(u16, s[1..3], 1)) != 3000 { return 13 }
  0
}

cnt := fn(s : Slice(u16), d : u64) -> u64 {
  if d == 0 { return u64(s.len) }
  cnt(s, d - 1)
}
ping := fn(s : Slice(u16), d : u64) -> u64 {
  if d == 0 { return u64(s.len) }
  pong(s, d - 1)
}
pong := fn(s : Slice(u16), d : u64) -> u64 {
  if d == 0 { return u64(s.len) + 1 }
  ping(s, d - 1)
}
drop1 := fn(s : Slice(u16)) -> u64 {
  if s.len == 0 { return 0 }
  1 + drop1(s[1..s.len])
}
l1 := fn(s : Slice(u16)) -> usize { l2(s) }
l2 := fn(s : Slice(u16)) -> usize { l3(s) }
l3 := fn(s : Slice(u16)) -> usize { l4(s) }
l4 := fn(s : Slice(u16)) -> usize { l5(s) }
l5 := fn(s : Slice(u16)) -> usize { l6(s) }
l6 := fn(s : Slice(u16)) -> usize { l7(s) }
l7 := fn(s : Slice(u16)) -> usize { l8(s) }
l8 := fn(s : Slice(u16)) -> usize { l9(s) }
l9 := fn(s : Slice(u16)) -> usize { l10(s) }
l10 := fn(s : Slice(u16)) -> usize { s.len }

## R3 — recursive, mutually recursive and ten-deep callees that only read `.len`
recursion := fn() -> u64 {
  a16 : [u16; 3] = [1000, 2000, 3000]
  if cnt(a16[0..3], 3) != 3 { return 14 }
  s := a16[0..3]
  if ping(s, 4) != 3 or ping(s, 3) != 4 { return 15 }
  if drop1(a16[0..3]) != 3 { return 16 }
  if l1(s) != 3 { return 17 }
  0
}

main := fn() -> u64 {
  mut r := reslice()
  if r != 0 { return r }
  r = field_store()
  if r != 0 { return r }
  r = field_path_store()
  if r != 0 { return r }
  r = reslice_args()
  if r != 0 { return r }
  r = recursion()
  if r != 0 { return r }
  42
}
## expect: run 42
