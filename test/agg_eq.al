## e2e — a BARE comparison operator over MULTI-WORD by-value aggregate operands now lowers to a CALL
## to the structural `base::derive::eq` / `lt` (Stdlib §2.6), instead of the former word-0-only scalar
## `cmpq` (a silent miscompile) or the fail-loud guard. Covers `==` / `!=` / `<` / `>` over 2-word
## structs, plus a NESTED-struct field difference (the top-level `!=` re-enters `eq` for the nested
## field, comparing every word). 1 + 2 + 4 + 8 + 16 + 11 = 42.
P := struct { x : u64, y : u64 }
Q := struct { a : P, b : u64 }
main := fn() -> u64 {
  p := P(x = 5, y = 7)
  q := P(x = 5, y = 7)   ## equal to p
  r := P(x = 5, y = 8)   ## differs from p in WORD 1 only
  mut acc : u64 = 0
  if p == q { acc = acc + 1 }              ## all fields equal → equal → +1
  if p == r { acc = acc + 100 } else { acc = acc + 2 }   ## word-1 difference detected → NOT equal → +2
  if p != r { acc = acc + 4 }              ## `!=` true → +4
  n1 := Q(a = P(x = 5, y = 7), b = 9)
  n2 := Q(a = P(x = 5, y = 8), b = 9)      ## nested `a` differs in word 1
  if n1 != n2 { acc = acc + 8 }            ## nested field difference detected → +8
  if p < r { acc = acc + 16 }              ## (5,7) < (5,8) lexicographically → +16
  if r > p { acc = acc + 11 }              ## (5,8) > (5,7) → +11
  acc
}
