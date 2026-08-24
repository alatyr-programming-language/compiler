## e2e — §2 operator overloading for a MULTI-WORD (2-word) user type: the canonical `Vec2 + Vec2 ->
## Vec2`. Both operands are 2-word structs pushed word-by-word into the inline scratch; the operator
## body sums each field and the 2-word result is delivered via the struct-return convention, then
## `r := p + q` is sized as `Vec2` so `r.x`/`r.y` read both words. (30,5) + (10,-3) = (40,2); 40+2 = 42.
Vec2 := struct { x : u64, y : u64 }
## The `.y` field carries a 2's-complement "negative" (`-3` stored in a u64), so `5 + (2^64-3) = 2`
## RELIES on modular (wrapping) addition — the `.y` sum needs an explicit `unchecked` scope, else the
## checked overflow guard (I11 / CG-8) traps the carry. Scoped per-field (not around the whole
## `Vec2(...)`) so the inline machinery still sees a bare struct-literal body for the struct return.
@inline + := fn(a : Vec2, b : Vec2) -> Vec2 { Vec2(x = a.x + b.x, y = unchecked { a.y + b.y }) }
main := fn() -> u64 {
  p := Vec2(x = 30, y = 5)
  q := Vec2(x = 10, y = -3)
  r := p + q
  r.x + r.y
}
