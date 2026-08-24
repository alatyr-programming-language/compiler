## fmt — a call-then-member `f(args).field` round-trips WITH its arguments (§5 tooling). This was a
## SILENT FORMATTER MISCOMPILE: the fmt driver parses with NO enum-name table, so the parser's
## `is_generic_enum_ctor` cannot tell a generic-enum ctor `E(T).V` from a plain `f(args).member` and
## rewrites the head `f(args)` to a bare `Var("f")`, DROPPING the arguments — fmt then emitted `f.field`
## (a different program, or a crash). fmt now recovers the whole `f(args)` verbatim from source when a
## `Field` base is a bare `Var` immediately followed by `(`. (A zero-arg `g().v` was never affected —
## `is_generic_enum_ctor` bails on empty parens.) mk(n) = P(v=n, w=n+1):
##   a=mk(20).v=20 ; b=mk(6).w=7 ; c=mk(arr[1]).v=mk(9).v=9 ; d=mk(2).v+mk(4).w=2+5=7 ; sum-1 = 42.
P := struct { v : u64, w : u64 }
mk := fn(n : u64) -> P { return P(v = n, w = n + 1) }
main := fn() -> u64 {
  a := mk(20).v
  b := mk(6).w
  arr : [u64; 2] = [3, 9]
  c := mk(arr[1]).v
  d := mk(2).v + mk(4).w
  return a + b + c + d - 1
}
