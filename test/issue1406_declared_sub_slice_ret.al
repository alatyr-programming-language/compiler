## #1406 — a function DECLARED `sub` that returns a range-view local of struct elements. The lower
## keyed the internal str-view `sub(s, start, len)` on the callee TEXT alone, so this call was routed
## to `emit_sub_pair`, which read argument positions 1 and 2 of a ONE-argument call: `arg_expr_at`
## answers null there and `emit_gas` dereferenced it. NON-VACUOUS on the parent c00eae90 (x86_64):
## the compiler itself died with SIGSEGV (exit 139) and printed no diagnostic; `alatyr check` on the
## same program answers 0, so the program is valid and only the spelling of the callee decided it.
## `sub` is not a keyword (Grammar §2.3) and no prelude declares it, so the declaration wins
## (Declarations §6.1) and the call lowers as the identical program under any other name does.
## Two elements of the view: `x.len` = 2, plus 40.
P := struct { a : u64, b : u64 }
sub := fn(s : Slice(P)) -> Slice(P) {
  r := s[0..2]
  r
}
main := fn() -> u64 {
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  x := sub(t[0..3])
  u64(x.len) + 40
}
## expect: run 42
