## e2e (Grammar §130 line 287 · OP-2): a compound assignment followed by a LATER plain `=` and a
## later `+=` on the SAME place. This is the shape that proves sema RECOVERED the compound token.
##
## `Stmt.Assign` does not distinguish a fresh binding `x := v` from a reassignment `x = v` — the
## parser erases the token, and `sema::assign_is_reassign` recovers it by scanning the source off the
## end of the name span. That scan carried its OWN table of compound spellings listing only
## `+= -= *= /=`, so once the lexer/parser learned `%= &= |= ^=` (bd1776a) those four took the
## BINDING path: sema re-pushed `x` as a fresh NON-`mut` local, and the NEXT write to `x` then read
## as a write to an immutable binding. A VALID program was REJECTED.
##
## Measured on the pre-fix build (`seed/alatyr build package.al` at ed53617 — whose `src/` and `lib/`
## are byte-identical to bd1776a, where the eight operators landed — then that `target/alatyr`):
##   mut x : u64 = 100 ; x &= 7 ; x = 10    -> alatyr: check: type mismatch at line 4 in <mod>, exit 1
##   identically for `%=`, `|=`, `^=`, and identically whether the following store is `=` or `+=`,
##   adjacent or several statements later. `+= -= *= /=` were unaffected (check exit 0).
## After the fix all eight check 0 and run to the values asserted below. On THIS file the pre-fix
## build stops at the first such store: "check: type mismatch at line 66" (the `e = 10` line).
##
## The `name.field` half is a REGRESSION GUARD, not a repro: `Stmt::FieldAssign` is always a store to
## an existing place, so it never consults the scan and measured green before AND after (check 0, the
## same values). It is the NAME half that makes this fixture red on the pre-fix build.
##
## The last four groups probe the SEAM IN BOTH ORDERS (AGENTS.md: "a fixture for the NEW form does not
## test the OLD one"): an old operator FIRST and a new one after it, then a plain store. Measured on
## the pre-fix build, each of the four was also rejected — `x += 7 ; x &= 3 ; x = 1` gave
## "type mismatch at line 5" — so the defect is symmetric in the order of the two operators, not a
## property of which one comes first.
##
## Expected exit: 42. A failure exits 100 + the failing group's 1-based index (max 116 < 126, so the
## fixture is cross-backend safe).
Acc := struct { v : u64 }
main := fn() -> u64 {
  mut bad : u64 = 0
  mut a : u64 = 100
  a += 7
  if bad == 0 and a != 107 { bad = 1 }
  a = 10
  if bad == 0 and a != 10 { bad = 1 }
  a += 5
  if bad == 0 and a != 15 { bad = 1 }
  mut b : u64 = 100
  b -= 7
  if bad == 0 and b != 93 { bad = 2 }
  b = 10
  if bad == 0 and b != 10 { bad = 2 }
  b += 5
  if bad == 0 and b != 15 { bad = 2 }
  mut c : u64 = 100
  c *= 7
  if bad == 0 and c != 700 { bad = 3 }
  c = 10
  if bad == 0 and c != 10 { bad = 3 }
  c += 5
  if bad == 0 and c != 15 { bad = 3 }
  mut d : u64 = 100
  d /= 7
  if bad == 0 and d != 14 { bad = 4 }
  d = 10
  if bad == 0 and d != 10 { bad = 4 }
  d += 5
  if bad == 0 and d != 15 { bad = 4 }
  ## the four operators the scan did not know about — each was a REJECTED valid program
  mut e : u64 = 100
  e %= 7
  if bad == 0 and e != 2 { bad = 5 }
  e = 10
  if bad == 0 and e != 10 { bad = 5 }
  e += 5
  if bad == 0 and e != 15 { bad = 5 }
  mut f : u64 = 100
  f &= 7
  if bad == 0 and f != 4 { bad = 6 }
  f = 10
  if bad == 0 and f != 10 { bad = 6 }
  f += 5
  if bad == 0 and f != 15 { bad = 6 }
  mut g : u64 = 100
  g |= 7
  if bad == 0 and g != 103 { bad = 7 }
  g = 10
  if bad == 0 and g != 10 { bad = 7 }
  g += 5
  if bad == 0 and g != 15 { bad = 7 }
  mut h : u64 = 100
  h ^= 7
  if bad == 0 and h != 99 { bad = 8 }
  h = 10
  if bad == 0 and h != 10 { bad = 8 }
  h += 5
  if bad == 0 and h != 15 { bad = 8 }
  ## a store that is SEVERAL statements away from the compound assignment, not adjacent
  mut i : u64 = 100
  i &= 58
  if bad == 0 and i != 32 { bad = 9 }
  mut spacer : u64 = 1
  spacer += 1
  if bad == 0 and spacer != 2 { bad = 9 }
  i = 7
  if bad == 0 and i != 7 { bad = 9 }
  ## the same four operators on a `name.field` place, each followed by `=` and `+=`
  mut fe := Acc(v = 100)
  fe.v %= 7
  if bad == 0 and fe.v != 2 { bad = 10 }
  fe.v = 10
  fe.v += 5
  if bad == 0 and fe.v != 15 { bad = 10 }
  mut ff := Acc(v = 100)
  ff.v &= 7
  if bad == 0 and ff.v != 4 { bad = 11 }
  ff.v = 10
  ff.v += 5
  if bad == 0 and ff.v != 15 { bad = 11 }
  mut fg := Acc(v = 100)
  fg.v |= 7
  if bad == 0 and fg.v != 103 { bad = 12 }
  fg.v = 10
  fg.v += 5
  if bad == 0 and fg.v != 15 { bad = 12 }
  mut fh := Acc(v = 100)
  fh.v ^= 7
  if bad == 0 and fh.v != 99 { bad = 12 }
  fh.v = 10
  fh.v += 5
  if bad == 0 and fh.v != 15 { bad = 12 }
  ## the seam in the OTHER order: an OLD operator first, then a NEW one, then a plain store
  mut ja : u64 = 100
  ja += 7
  if bad == 0 and ja != 107 { bad = 13 }
  ja %= 51
  if bad == 0 and ja != 5 { bad = 13 }
  ja = 5
  ja += 1
  if bad == 0 and ja != 6 { bad = 13 }
  mut jb : u64 = 100
  jb -= 7
  if bad == 0 and jb != 93 { bad = 14 }
  jb &= 58
  if bad == 0 and jb != 24 { bad = 14 }
  jb = 5
  jb += 1
  if bad == 0 and jb != 6 { bad = 14 }
  mut jc : u64 = 100
  jc *= 2
  if bad == 0 and jc != 200 { bad = 15 }
  jc |= 51
  if bad == 0 and jc != 251 { bad = 15 }
  jc = 5
  jc += 1
  if bad == 0 and jc != 6 { bad = 15 }
  mut jd : u64 = 100
  jd /= 4
  if bad == 0 and jd != 25 { bad = 16 }
  jd ^= 51
  if bad == 0 and jd != 42 { bad = 16 }
  jd = 5
  jd += 1
  if bad == 0 and jd != 6 { bad = 16 }
  if bad != 0 { return 100 + bad }
  return 42
}
