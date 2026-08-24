## e2e — SYN-4 (Grammar §2.6): the operator-name BINDING-HEAD exception. `base := 40` ends a value
## binding with a BARE OPERAND (an int literal); the very next line `+ := fn(…)` is an operator-function
## declaration whose NAME is the glyph. Before the fix, the greedy binary-operator fold consumed the
## line-leading `+` as a continuation of `40` (folding toward `40 + fn(…)`) and then hit the following
## `:=`, a PARSE ERROR. The fix stops the fold at an operator glyph IMMEDIATELY followed by `:=`/`:` (a
## binding head — never a valid mid-expression sequence), so the preceding newline stays a declaration
## separator and the operator decl parses on its own line without an `@inline`/prefix cue. 40 + 2 -> 42.
Money := struct { cents : u64 }
base := 40
+ := fn(a : Money, b : Money) -> u64 {
  a.cents + b.cents
}
main := fn() -> u64 {
  p := Money(cents = base)
  q := Money(cents = 2)
  p + q
}
