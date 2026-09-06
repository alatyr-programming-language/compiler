## #419 — the unary prefixes `-` and `~` take the POSTFIX EXPRESSION as their operand, so a postfix
## step that follows belongs to the OPERAND and not to the prefix's result.
##
## Grammar §3.4 writes the unary level as
##   unary-expr  ::= ( "-" | "~" | "not" ) unary-expr | postfix-expr
##   postfix-expr ::= primary { postfix }
## with `.` field, `.` tuple-index, `.f()` UFCS, `(` call `)`, `[` index `]` and `?` as the postfix
## ops, and §4 puts that whole postfix family at level 1 against the unary prefixes at level 2 —
## postfix binds TIGHTER. So `-a[i]` is `-(a[i])`, `~a[i]` is `~(a[i])` and `-p.b` is `-(p.b)`.
##
## The parser took both operands at the PRIMARY level (`p_factor`), returning before `p_field`'s
## postfix loop, so `-a[i]` parsed as `(-a)[i]`. The index base was then a nameless `Unchecked` /
## `Bin` node that no `Index` recogniser in lower matches; it fell to the untyped tail of
## `emit_index_addr`, which resolves a nameless base to frame SLOT 0 — a clean compile that read
## unrelated memory. Same sink and same shape of cause as `unchecked`'s #410, a different operator.
##
## Measured on the parent (origin/main 70ba9b3, `target/debug/alatyr`), each row built as its own
## standalone program and each binary's own `$?` read outside any pipeline. Every mis-bound row read
## frame slot 0; `->` is the parent, `=>` is this tree:
##
##   rc 101  -xs[1]          ->   0  =>  42      rc 107  -t.1            ->   0  =>  42
##   rc 102  -xs[0]          ->   0  =>  71      rc 108  -xs[1].add1()   -> 255  =>  43
##   rc 103  ~~xs[2]         ->   5  =>  93      rc 112  (-xs[3])        -> 255  =>  55
##   rc 104  -v[1]           ->   0  =>  93
##   rc 105  -p.b            ->   0  =>  42      rc 109  -(xs[1])        ->  42  =>  42  CONTROL
##   rc 106  ~~p.a           ->   0  =>  71      rc 110  ~a & b          ->  58  =>  58  CONTROL
##                                               rc 111  -c % d          ->   3  =>   3  CONTROL
##
## Read rc 103 and rc 108 before trusting any `!= 0` shortcut: the SAME defect returned 5 and 255
## there, because frame slot 0 holds whatever that frame happens to keep — a saved register or a
## return address on another shape. That is why the neighbours here are non-zero and pairwise
## distinct (71, 42, 93, 55) and why each check owns its own failure code from 100 rather than being
## folded into one arithmetic total (#386): no `good * K + bad`, no commutative sum, every exit < 126.
##
## rc 112 is deliberately the OUTER-parenthesized spelling `(-xs[3])`. Grouping the whole prefix
## expression did NOT rescue it on the parent — only parenthesizing the OPERAND (`-(xs[1])`, rc 109)
## did — which is exactly what makes this a binding defect and not an arithmetic one.
##
## rc 109-111 are the CONTROLS and were already correct on the parent: the operand-parenthesized
## spelling keeps its meaning, and every BINARY operator still binds LOOSER than the prefix, so the
## fix moves the POSTFIX boundary only.
##
## The fixture stays inside the scalar array/slice/struct/tuple kernel, so ALL FOUR backends run it.
## Whole-fixture exit, parent -> this tree: x86_64 101 -> 42, aarch64 133 -> 42, riscv64 133 -> 42,
## wat 134 -> 42. The three non-x86 backends TRAPPED on the parent rather than producing a second
## wrong value, so only x86_64 could report the defect as an exit code.
P := struct { a : u64, b : u64 }

add1 := fn(v : u64) -> u64 { v + 1 }

main := fn() -> u64 {
  xs : [u64; 4] = [71, 42, 93, 55]
  ## a fixed-array local base — the most ordinary index there is.
  n1 := -xs[1]
  if 0 - n1 != 42 { return 101 }
  ## element 0 is non-zero, so reading the frame's slot 0 stays distinguishable from reading xs[0].
  n0 := -xs[0]
  if 0 - n0 != 71 { return 102 }
  ## `~~x` is `x`, so the double complement recovers the element the source named.
  if u64(~~xs[2]) != 93 { return 103 }
  ## a typed slice base — `xs[1..3]` is the view {42, 93}, so element 1 is 93.
  v := xs[1..3]
  n2 := -v[1]
  if 0 - n2 != 93 { return 104 }
  ## a struct FIELD base: `-p.b` is `-(p.b)`, not `(-p).b`.
  p := P(a = 71, b = 42)
  n3 := -p.b
  if 0 - n3 != 42 { return 105 }
  if u64(~~p.a) != 71 { return 106 }
  ## a TUPLE component base — `.N` is the same postfix step as `.f`.
  t := (71, 42)
  n4 := -t.1
  if 0 - n4 != 42 { return 107 }
  ## a UFCS call applied to an index: the whole postfix CHAIN is the operand.
  n5 := -xs[1].add1()
  if 0 - n5 != 43 { return 108 }
  ## CONTROL — the parenthesized spelling was already right and must stay right.
  n6 := -(xs[1])
  if 0 - n6 != 42 { return 109 }
  ## CONTROL — `&` still binds LOOSER than `~`, so this is `(~a) & b` and not `~(a & b)`:
  ## ~5 = …11111010, & 63 = 58. (`~(5 & 63)` would be the all-ones complement of 5, not 58.)
  a : u64 = 5
  b : u64 = 63
  if u64(~a & b) != 58 { return 110 }
  ## CONTROL — `%` still binds LOOSER than unary `-`, so this is `(0 - c) % d`. 2^64 ≡ 1 (mod 5),
  ## so (2^64 - 3) mod 5 = 3; `0 - (c % d)` would be 2^64-3, which is not 3.
  c : u64 = 3
  d : u64 = 5
  if -c % d != 3 { return 111 }
  ## Grouping the WHOLE prefix expression is not the same rescue as grouping the OPERAND: on the
  ## parent `(-xs[3])` still parsed as `((-xs))[3]`, because the outer parens close after the index.
  n7 := (-xs[3])
  if 0 - n7 != 55 { return 112 }
  return 42
}
