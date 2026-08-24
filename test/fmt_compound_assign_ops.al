## e2e fmt (Grammar §130 line 287 · OP-2): `alatyr fmt` must re-emit ALL EIGHT compound-assignment
## spellings VERBATIM. The parser desugars `x op= e` into `Assign(x, Bin(op, x, e))`, so the surface
## glyph survives only in the source; fmt recovered it with two private probes that disagreed with
## each other AND with the grammar — one accepted `+ - * / %`, the other only `+ - * /`.
##
## NOTE ON THE NEEDLES: `fmt_test_has_all` greps the WHOLE formatted file, and fmt preserves this
## header verbatim — so this header must never contain a needle's literal text, or the assertion
## would pass by matching its own documentation. (It did, first try: the pre-fix table below was
## written out with each operator AND its operand, and all ten needles "passed" on the PRE-FIX
## build. Now they fail there, 4 of 10.) Hence the operators below are named without operands.
##
## Measured on the pre-fix build (Stage1 from the seed at ed53617 — whose `src/` and `lib/` are
## byte-identical to bd1776a, where the eight operators landed), formatting these same statements:
##   `+=` `-=` `*=` `/=`  re-emitted faithfully
##   `%=`                 the compound spelling was LOST — re-emitted as an expanded plain store
##                        (behaviour-identical, but not what the user wrote)
##   `&=` `|=` `^=`       rewritten into a DECLARATION, `:=` — fmt turned an assignment into a
##                        fresh, IMMUTABLE, shadowing binding of the same name
## and the pre-fix build did not even accept this source: `check` exited 1 with
## "type mismatch at line 62" (the plain store in the `k` group below), the sema half of the same defect.
##
## The `m` group guards the OTHER direction: a bare binary EXPRESSION statement must NOT be read as
## a compound assignment. Its needle would also be satisfied by fmt rewriting it into a `:=`
## DECLARATION of the same name, so the run assertion carries that half: that spelling would bind a
## fresh `m` holding 50 and the group would exit 107.
##
## Group legend (in-body comments are dropped by fmt, so they live here): `a` runs the four
## already-faithful glyphs and returns to 100; `e` `f` `g` `h` are `%=` `&=` `|=` `^=`; `k` is a
## compound assignment followed by a plain store — if fmt renders the first as a `:=` declaration the
## FORMATTED program no longer builds (an immutable write), so `fmt_test`'s run step fails too; `m` is
## the bare expression statement; `s.v` a `name.field` place.
##
## Known and unchanged by this fixture: a compound assignment on a `name.field` place is re-emitted
## EXPANDED for all eight glyphs. `Stmt::FieldAssign` has no compound-spelling probe at all; the
## rendering is behaviour-identical (a `name.field` place has no side effects to re-run) and
## idempotent, so it is a fidelity gap, not a defect. Asserted below only as "runs to the same value".
##
## Expected exit: 42. A failure exits 100 + the failing group's index (max 108 < 126).
Acc := struct { v : u64 }
main := fn() -> u64 {
  mut bad : u64 = 0
  mut a : u64 = 100
  a += 7
  a -= 7
  a *= 7
  a /= 7
  if bad == 0 and a != 100 { bad = 1 }
  mut e : u64 = 100
  e %= 51
  if bad == 0 and e != 49 { bad = 2 }
  mut f : u64 = 100
  f &= 58
  if bad == 0 and f != 32 { bad = 3 }
  mut g : u64 = 100
  g |= 51
  if bad == 0 and g != 119 { bad = 4 }
  mut h : u64 = 100
  h ^= 51
  if bad == 0 and h != 87 { bad = 5 }
  mut k : u64 = 100
  k &= 58
  k = 42
  if bad == 0 and k != 42 { bad = 6 }
  mut m : u64 = 100
  m - 50
  if bad == 0 and m != 100 { bad = 7 }
  mut s := Acc(v = 100)
  s.v &= 58
  if bad == 0 and s.v != 32 { bad = 8 }
  if bad != 0 { return 100 + bad }
  return 42
}
