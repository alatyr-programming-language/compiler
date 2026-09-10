## e2e (#422) — a RANGE SLICE used DIRECTLY as an index base, `xs[lo..hi][i]`, on ALL FOUR backends.
## Grammar §3.4 (pin `b4e7979`) writes `postfix-expr ::= primary { postfix }` with both `"[" expr "]"`
## and the range form among the postfix ops, so this is ONE primary plus TWO postfix steps and needs
## no intermediate binding; `v := xs[lo..hi]; v[i]` is the SAME access one binding later and has
## always answered correctly on every backend. The two spellings disagreeing IS the defect.
##
## x86_64 was closed by PR #498 (`emit_arr_slice_pair` above `emit_index_addr`'s tail). The residual
## this fixture pins is the other three: measured on `main` `d590e90`, every direct row below was
## a133 / rv133 / wasm134 — a fail-loud trap, because every arm of those backends' `Expr::Index`
## chains keys on a bare `Var` base and an `Expr::Slice` base reached none of them. The bound rows
## answered 42 / 93 / 55 on the same compiler, which is why a bare "it traps" is not the pass
## condition here: the two spellings must name the SAME byte.
##
## Every code below names the WRONG ANSWER it rules out rather than only the failing line (#386),
## because on this shape a plausible word is exactly what a partial fix produces: a zero (the frame
## slot 0 the x86 sink used to read), `lo` ignored (element 0 of the BASE array), one element either
## side of the intended one, and the view's own LENGTH in place of its element. The neighbours 71,
## 42, 93, 55 are non-zero and pairwise distinct, and `xs[3..4]` is a LENGTH-1 view whose length (1)
## and element (55) differ, so neither a zero nor a returned length can pass by coincidence.
##
## No index WRITE and no struct field appears here on purpose: #621 (a `Slice(T)` FIELD traps on
## a64/rv64/wasm), #630 (x86_64 refuses a field fixed array through a nested owner) and #631 (on
## wasm an indexable write followed by a later structural local traps 134) are open, and a fixture
## that walked into one of them would freeze that defect into four oracle rows.
main := fn() -> u64 {
  xs : [u64; 4] = [71, 42, 93, 55]
  ## the plain neighbours first: if these move, nothing below is attributable
  if xs[1] != 42 { return 1 }
  v := xs[1..3]
  if v[0] != 42 { return 2 }
  if v[1] != 93 { return 3 }
  ## #422 — element 0 of the view {42, 93}
  d0 := xs[1..3][0]
  if d0 == 0 { return 4 }                    ## a zero word / the frame-slot-0 read
  if d0 == 71 { return 5 }                   ## `lo` ignored: element 0 of the BASE array
  if d0 == 93 { return 6 }                   ## one element PAST the view's start
  if d0 == 2 { return 7 }                    ## the view's LENGTH instead of its element
  if d0 != 42 { return 8 }                   ## any other wrong word
  d1 := xs[1..3][1]
  if d1 == 0 { return 9 }
  if d1 == 42 { return 10 }                  ## one element BEFORE (the view's own element 0)
  if d1 == 55 { return 11 }                  ## one element PAST the view's end
  if d1 != 93 { return 12 }
  ## a LENGTH-1 view: its length (1) and its element (55) differ, so answering the length fails here
  d2 := xs[3..4][0]
  if d2 == 1 { return 13 }
  if d2 == 0 { return 14 }
  if d2 != 55 { return 15 }
  ## the zero-start control pins the other half — adding a zero offset must not shift the element
  if xs[0..4][1] != 42 { return 16 }
  ## the bounds need not be literals
  lo := 1
  hi := 3
  if xs[lo..hi][0] != 42 { return 17 }
  if xs[lo..hi][1] != 93 { return 18 }
  ## the two spellings of ONE access must agree — the disagreement IS #422
  if v[0] != xs[1..3][0] { return 19 }
  if v[1] != xs[1..3][1] { return 20 }
  ## bounds AND index recovered through ANOTHER checked index. On WASM the index is parked in a
  ## scratch LOCAL while the bound `hi - lo` is evaluated, and every other checked index parks in
  ## the FIRST scratch, so this row is the control that the two parks do not collide.
  ns : [u64; 2] = [1, 3]
  ms : [u64; 2] = [1, 0]
  if xs[ns[0]..ns[1]][ms[1]] != 42 { return 21 }
  if xs[ns[0]..ns[1]][ms[0]] != 93 { return 22 }
  ## an `unchecked` scope drops the bounds check and must keep the SAME address math (CG-7): index 2
  ## of a two-element view names `xs[3]` = 55, which also proves `lo` is folded into the pointer.
  if unchecked xs[1..3][2] != 55 { return 23 }
  ## two base arrays in one function must not share a view
  ys : [u64; 4] = [11, 22, 33, 44]
  if ys[1..3][0] != 22 { return 24 }
  if xs[1..3][0] != 42 { return 25 }
  ## an INFERRED array local (no type annotation) reaches the same recognizer as an annotated one
  zs := [77, 88, 99, 66]
  if zs[1..3][1] != 99 { return 26 }
  ## the direct read composes with ordinary arithmetic and as a call argument
  if xs[1..3][0] + ys[0..2][1] != 64 { return 27 }
  ## NOT here: `xs[lo..hi].len` on a direct view. It is a `Field` over an `Expr::Slice`, a different
  ## arm entirely, and it still traps a133 / rv133 / wasm134 on this tree — asserting it would pin a
  ## shape this change does not deliver. x86_64 answers 2 for it; that asymmetry stays with #422.
  42
}
