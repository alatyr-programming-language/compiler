## Issue #507 CONTROL — the over-reach fence. The fix makes the statement-position name walk DESCEND
## into `Bin` operands, which is the one arm that used to answer "clean" for everything. This fixture
## exercises the LEGAL shapes that now pass through that descent and must all still compile and run:
## a struct-field operand, a plain local operand, `and` / `or` / `not` chains, a nested user call as
## an operand, a comparison against a module-level constant used BEFORE its textual declaration, and
## the same shapes in a `while` condition — which previously ran no name walk at all and now runs the
## `if` condition's.
##
## Every rejection code is distinct and below 126, and nothing is summed into a single total.
Rec := struct { ek : u64, is_ref : bool }

double := fn(n : u64) -> u64 { n * 2 }

main := fn() -> u64 {
  r := Rec(ek = 4, is_ref = false)

  ## a struct-field operand, and an `and` chain over two of them
  if r.ek != 4 { return 1 }
  if r.ek == 4 and r.is_ref == false { } else { return 2 }

  ## a plain local operand, an `or` chain, and `not`
  q : u64 = 7
  if q == 7 or q == 8 { } else { return 3 }
  if not (q == 6) { } else { return 4 }

  ## a bare bool local as the whole condition, and as an operand
  flag := true
  if flag { } else { return 5 }
  if flag == true and q == 7 { } else { return 6 }

  ## a nested call as an operand. The comptime type builtin `size(T)` is deliberately NOT exercised
  ## here: it TRAPS at run on aarch64/riscv64/wasm on the parent compiler too (a pre-existing backend
  ## gap, unrelated to this check), and a cross-backend fixture must stay below 126. The descent's
  ## type-builtin tolerance is instead proved by the compiler's own library, which keeps building:
  ## `lib/alloc/vec.al:266` has `if quot != size(T)` and `lib/alloc/deque.al:50` has
  ## `while k < size(T)` — a type-builtin operand in an `if` and in a `while` condition.
  if double(q) != 14 { return 7 }

  ## a module-level constant compared BEFORE its textual declaration (the walk resolves a global
  ## whole-program, not prefix-only)
  if LATER_CONST != 11 { return 9 }

  ## `while`, which previously had no name walk of its own: a compound condition over a local, a
  ## parameter-shaped operand through a helper, and a struct field
  mut i : u64 = 0
  while i < 3 and i != 9 { i = i + 1 }
  if i != 3 { return 10 }

  mut j : u64 = 0
  while double(j) < 6 { j = j + 1 }
  if j != 3 { return 11 }

  mut s := Rec(ek = 0, is_ref = false)
  while s.ek < 2 { s.ek = s.ek + 1 }
  if s.ek != 2 { return 12 }

  ## A discarded `Bin` expression statement over DECLARED names is deliberately not exercised here:
  ## on the wasm backend `q + 1` followed by a tail `42` returns 8 on the PARENT compiler too, a
  ## pre-existing lowering wrong value unrelated to this check. The undeclared form of that position
  ## is covered by issue507_exprstmt_operand_unbound, which is a reject and never runs.

  42
}

LATER_CONST : u64 = 11
