## e2e — TYP-10 slice C: the FULL generalized `uint(N)` recipe at a THIRD width (Types §7,
## design/decisions/types.md TYP-10). This program declares NOTHING locally: the bare `uint(256)`
## instantiation + the bare `u128` name pull `lib/base/u128.al` in through the cli.al ambient
## injection (the `uint(`/`u128` source scan), which defines the prelude type-function
## `uint := fn(comptime N : u64) -> type { struct { words : [u64; N/64] } }`, the alias
## `u128 := uint(128)`, and the whole `@inline` generic-operator set (`+ - * / %` + the six
## comparisons). `uint(256)` is 4 little-endian words (word 0 = LSW).
##
## Coverage (each check adds its share; only the full set reaches 42):
##   +  : {MAX,MAX,0,0} + {1,0,0,0} = {0,0,1,0}         — carry ripples across TWO word boundaries
##   -  : {0,0,1,0} - {1,0,0,0}     = {MAX,MAX,0,0}     — borrow ripples across two boundaries
##   *  : {0,2,0,0} * {0,4,0,0}     = {0,0,8,0}         — 2^65·2^66 = 2^131, cross-word schoolbook
##        {MAX,MAX,MAX,MAX} * {2,0,0,0} = {MAX-1,MAX,MAX,MAX} — keeps the LOW 256 bits (mod 2^256)
##   /  : {0,0,6,0} / {0,2,0,0}     = {0,3,0,0}         — 6·2^128 / 2·2^64 = 3·2^64 (divisor has
##        bits in a HIGH word; quotient lands in word 1 — comptime-unrolled long division)
##   %  : {0,0,13,0} % {0,5,0,0}    = {0,3,0,0}         — 13·2^128 mod 5·2^64 = 3·2^64
##   cmp: {0,0,0,1} vs {MAX,MAX,MAX,0} — the HIGH word decides `>`/`<` despite every low word
##        saying the opposite; `>=`/`<=`/`==` at equality; `!=` on a difference
##   alias: `u128(words=[40,0])` (the ALIAS constructor) + `uint(128)(words=[2,0])` (the direct
##        constructor) route the SAME generic `+` across the two names — u128 ≡ uint(128)
## 42 = 6 (+) + 6 (-) + 3+3 (*) + 6 (cmps) + 6 (/) + 6 (%) + 6 (alias).
main := fn() -> u64 {
  MAX : u64 = 18446744073709551615

  a := uint(256)(words = [MAX, MAX, 0, 0])
  b := uint(256)(words = [1, 0, 0, 0])
  s := a + b

  c := uint(256)(words = [0, 0, 1, 0])
  d := uint(256)(words = [1, 0, 0, 0])
  df := c - d

  e := uint(256)(words = [0, 2, 0, 0])
  f := uint(256)(words = [0, 4, 0, 0])
  p := e * f

  g := uint(256)(words = [MAX, MAX, MAX, MAX])
  h := uint(256)(words = [2, 0, 0, 0])
  p2 := g * h

  n1 := uint(256)(words = [0, 0, 6, 0])
  d1 := uint(256)(words = [0, 2, 0, 0])
  q := n1 / d1

  n2 := uint(256)(words = [0, 0, 13, 0])
  d2 := uint(256)(words = [0, 5, 0, 0])
  m := n2 % d2

  x := uint(256)(words = [0, 0, 0, 1])
  y := uint(256)(words = [MAX, MAX, MAX, 0])

  aa := u128(words = [40, 0])
  bb := uint(128)(words = [2, 0])
  cc := aa + bb

  mut acc : u64 = 0
  if s.words[2] == 1 and s.words[1] == 0 and s.words[0] == 0 and s.words[3] == 0 { acc = acc + 6 }
  if df.words[0] == MAX and df.words[1] == MAX and df.words[2] == 0 and df.words[3] == 0 { acc = acc + 6 }
  if p.words[2] == 8 and p.words[3] == 0 and p.words[1] == 0 { acc = acc + 3 }
  if p2.words[0] == 18446744073709551614 and p2.words[1] == MAX and p2.words[2] == MAX and p2.words[3] == MAX { acc = acc + 3 }
  if x > y { acc = acc + 1 }
  if y < x { acc = acc + 1 }
  if x >= x { acc = acc + 1 }
  if x <= x { acc = acc + 1 }
  if x == x { acc = acc + 1 }
  if x != y { acc = acc + 1 }
  if y > x { acc = acc + 100 }              ## MUST be false (high word 0 < 1)
  if q.words[1] == 3 and q.words[0] == 0 and q.words[2] == 0 { acc = acc + 6 }
  if m.words[1] == 3 and m.words[0] == 0 and m.words[2] == 0 { acc = acc + 6 }
  if cc.words[0] == 42 and cc.words[1] == 0 { acc = acc + 6 }
  return acc
}
