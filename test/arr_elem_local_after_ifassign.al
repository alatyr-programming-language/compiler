## e2e — SCANNER guard for the aggregate array-element WRITE statements. `xs[i].f = v`
## (Stmt::IndexFieldAssign) and `xs[i] = Lit` (Stmt::IndexAssign) declare no local, but a body scanner
## that STOPS at an unrecognised statement would hide every local declared AFTER them: `t` would lose
## its frame slot and its ELEMENT struct type, and `u` its slot — a silent frame corruption, not a
## trap. So the place-assigns come FIRST here, before the two locals that must still resolve.
##   ps[1].y = 40 ; ps[0] = P(5, 6) ; t := ps[1] = (3, 40) ; u := ps[0].y = 6
##   3 + 40 + 6 = 49
P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut ps : [P; 2] = [P(x = 1, y = 2), P(x = 3, y = 4)]
  mut i := 1
  ps[i].y = 40                           ## IndexFieldAssign BEFORE the locals below are declared
  ps[0] = P(x = 5, y = 6)                ## IndexAssign (whole element) also before them
  t := ps[1]                             ## a local declared AFTER both: keeps its element-wide slot
  u := ps[0].y                           ## a second later local: keeps its scalar slot
  if t.x != 3 { return 1 }               ## the field write touched word 1 only
  if ps[0].x != 5 { return 2 }           ## the whole-element write landed on word 0 too
  t.x + t.y + u                          ## 3 + 40 + 6 = 49
}
