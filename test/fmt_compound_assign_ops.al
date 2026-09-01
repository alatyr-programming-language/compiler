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
## Issue #343: the shared source recovery in `ast` capped its whitespace scan a fixed 512 bytes past
## the place's name span, so an assignment separated from its operator by a longer whitespace run was
## reclassified as a DECLARATION. `boundary512` / `boundary513` straddle that exact threshold (the old
## cap accepted 512 and lost 513); the eight `long_*` groups repeat it for every glyph; `plain343`,
## `fresh343` and `cmp343` are the non-compound controls (`=` stays an assignment, `:=` stays a fresh
## binding, `==` stays an expression). `GMOD343` is the heaviest witness: `sema` tests the module-`mut`
## -global predicate AFTER the reassignment predicate while `lower`'s slot collection tests it BEFORE,
## so a lost reassignment made those two consumers disagree about one statement — the drift this file's
## single-source recovery exists to prevent. Every group carries its OWN index, so a red run names the
## group that broke; the unique names also keep the formatter needles out of this explanatory header.
##
## The last three groups cover the SAME fixed window in the SAME helper family, on the DECLARATION side
## (Declarations §3.3). A typed no-initializer local carries its type only in source, so `lower` recovers
## it by the same forward scan. Past the old cap the annotation was lost and the binding was reserved as
## ONE SCALAR WORD: a two-field element array's stride collapsed from 16 bytes to 8 and element 1 read
## element 0's second word — measured standalone on the parent (7774f91) as a clean 8-byte stride
## (`imulq $8` where `imulq $16` is owed), accepted by `check` and wrong only at run time. The parser had
## its own copy of the no-initializer decision and, past its own cap, ABSORBED the following statement
## into the declaration, so the next binding silently took the wrong value; when nothing absorbable
## followed it refused the valid file outright.
##
## Expected exit: 42. A failure exits 100 + the failing group's index (max 125 < 126).
Acc := struct { v : u64 }
Row := struct { a : u64, b : u64 }
mut GMOD343 : u64 = 1
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
  mut boundary512 : u64 = 1
  boundary512                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                += 1
  if bad == 0 and boundary512 != 2 { bad = 9 }
  boundary512 = 9
  if bad == 0 and boundary512 != 9 { bad = 9 }
  mut boundary513 : u64 = 1
  boundary513                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 += 1
  if bad == 0 and boundary513 != 2 { bad = 10 }
  boundary513 = 9
  if bad == 0 and boundary513 != 9 { bad = 10 }
  mut long_add : u64 = 1
  long_add                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 += 1
  if bad == 0 and long_add != 2 { bad = 11 }
  long_add = 9
  if bad == 0 and long_add != 9 { bad = 11 }
  mut long_sub : u64 = 3
  long_sub                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 -= 1
  if bad == 0 and long_sub != 2 { bad = 12 }
  long_sub = 9
  if bad == 0 and long_sub != 9 { bad = 12 }
  mut long_mul : u64 = 2
  long_mul                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 *= 3
  if bad == 0 and long_mul != 6 { bad = 13 }
  long_mul = 9
  if bad == 0 and long_mul != 9 { bad = 13 }
  mut long_div : u64 = 8
  long_div                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 /= 2
  if bad == 0 and long_div != 4 { bad = 14 }
  long_div = 9
  if bad == 0 and long_div != 9 { bad = 14 }
  mut long_rem : u64 = 8
  long_rem                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 %= 3
  if bad == 0 and long_rem != 2 { bad = 15 }
  long_rem = 9
  if bad == 0 and long_rem != 9 { bad = 15 }
  mut long_and : u64 = 6
  long_and                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 &= 3
  if bad == 0 and long_and != 2 { bad = 16 }
  long_and = 9
  if bad == 0 and long_and != 9 { bad = 16 }
  mut long_or : u64 = 2
  long_or                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |= 1
  if bad == 0 and long_or != 3 { bad = 17 }
  long_or = 9
  if bad == 0 and long_or != 9 { bad = 17 }
  mut long_xor : u64 = 6
  long_xor                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 ^= 3
  if bad == 0 and long_xor != 5 { bad = 18 }
  long_xor = 9
  if bad == 0 and long_xor != 9 { bad = 18 }
  mut plain343 : u64 = 1
  plain343                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 = 2
  if bad == 0 and plain343 != 2 { bad = 19 }
  mut fresh343 : u64 = 4
  fresh343                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 := 5
  if bad == 0 and fresh343 != 5 { bad = 20 }
  mut cmp343 : u64 = 2
  cmp343                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 == 2
  if bad == 0 and cmp343 != 2 { bad = 21 }
  GMOD343                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 += 1
  if bad == 0 and GMOD343 != 2 { bad = 22 }
  GMOD343 = 9
  if bad == 0 and GMOD343 != 9 { bad = 22 }
  mut xs343                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : [Row; 2]
  xs343[0] = Row(a = 11, b = 12)
  xs343[1] = Row(a = 21, b = 31)
  if bad == 0 and xs343[1].b != 31 { bad = 23 }
  if bad == 0 and xs343[0].a != 11 { bad = 23 }
  mut scal343                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : u64
  scal343 = 7
  if bad == 0 and scal343 != 7 { bad = 24 }
  mut idle343                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        : u64
  mut seen343 : u64 = 5
  if bad == 0 and seen343 != 5 { bad = 25 }
  idle343 = 9
  if bad == 0 and idle343 != 9 { bad = 25 }
  if bad != 0 { return 100 + bad }
  return 42
}
