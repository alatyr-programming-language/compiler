## e2e (Grammar §130 line 287 · OP-2 · Memory §1): compound assignment for ALL EIGHT glyph
## operators `+= -= *= /= %= &= |= ^=` on a NAME place and on a `name.field` place.
##
## Before the fix the lexer emitted two-char tokens for only FOUR of them, so `%=`, `&=`, `|=`
## and `^=` lexed as two tokens (`&` then `=`), matched no statement head, were parsed as the
## enclosing function's trailing RETURN expression, and the store was SILENTLY DROPPED: the
## program compiled clean and the place kept its old value. `mut x : u64 = 100 ; x &= 58` left
## x at 100 instead of 32 — a wrong value, the one forbidden outcome (I11).
##
## The operand pair 100 and 7 makes all eight results PAIRWISE DISTINCT — 107, 93, 700, 14, 2,
## 4, 103, 99 — so substituting any one operator for any other fails that operator's own check
## (with 100 and 58 the `-=` and `%=` results would both be 42 and the two could be confused).
##
## Expected exit: 42 (every operator agrees). A failure exits 100 + the operator's 1-based
## index in the grammar's order, so the exit code names which operator broke.
Acc := struct { v : u64 }
main := fn() -> u64 {
  mut bad : u64 = 0
  mut a : u64 = 100
  a += 7
  if bad == 0 and a != 107 { bad = 1 }
  mut b : u64 = 100
  b -= 7
  if bad == 0 and b != 93 { bad = 2 }
  mut c : u64 = 100
  c *= 7
  if bad == 0 and c != 700 { bad = 3 }
  mut d : u64 = 100
  d /= 7
  if bad == 0 and d != 14 { bad = 4 }
  mut e : u64 = 100
  e %= 7
  if bad == 0 and e != 2 { bad = 5 }
  mut f : u64 = 100
  f &= 7
  if bad == 0 and f != 4 { bad = 6 }
  mut g : u64 = 100
  g |= 7
  if bad == 0 and g != 103 { bad = 7 }
  mut h : u64 = 100
  h ^= 7
  if bad == 0 and h != 99 { bad = 8 }
  ## the `name.field` place — the same eight-operator surface through `FieldAssign`
  mut fa := Acc(v = 100)
  fa.v %= 7
  if bad == 0 and fa.v != 2 { bad = 9 }
  mut fb := Acc(v = 100)
  fb.v &= 7
  if bad == 0 and fb.v != 4 { bad = 10 }
  mut fc := Acc(v = 100)
  fc.v |= 7
  if bad == 0 and fc.v != 103 { bad = 11 }
  mut fd := Acc(v = 100)
  fd.v ^= 7
  if bad == 0 and fd.v != 99 { bad = 12 }
  ## `&`, `|`, `^`, `%` must still lex and parse as ORDINARY BINARY operators (no over-rejection)
  if bad == 0 and (100 & 7) != 4 { bad = 13 }
  if bad == 0 and (100 | 7) != 103 { bad = 14 }
  if bad == 0 and (100 ^ 7) != 99 { bad = 15 }
  if bad == 0 and (100 % 7) != 2 { bad = 16 }
  if bad != 0 { return 100 + bad }
  return 42
}
