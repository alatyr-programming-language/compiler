## e2e (formerly a build_reject) — the classic aggregate WORD-1 silent miscompile is now COMPILED
## CORRECTLY: a bare `a == b` over two 2-word `P` structs routes to `base::derive::eq`, which compares
## EVERY word, so `P(5, 7) == P(5, 9)` (equal in word 0, differing only in word 1) is correctly NOT
## equal — the former scalar `cmpq` compared word 0 alone and wrongly reported EQUAL. Returns 42.
P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  a := P(x = 5, y = 7)
  b := P(x = 5, y = 9)   ## differs in word 1 only
  if a == b { 0 } else { 42 }
}
