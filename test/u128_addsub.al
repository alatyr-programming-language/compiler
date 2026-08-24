## e2e — ROADMAP §8.4 part 1, TYP-10 slice C (Types §3/§7, TYP-2 / TYP-10 / D23 / D24;
## spec/20-types.md §7 "Wider-than-native named integers"; operators.md OP-1). `u128` is a PRELUDE
## name — the `u128 ≡ uint(128)` ALIAS of the generalized `uint(N)` recipe (lib/base/u128.al: a
## nominal struct of N/64 little-endian `u64` words, word 0 = the low 64 bits, ambiently injected),
## NOT a compiler built-in and NOT backend register-pair magic. Its `+`/`-` are `@inline` GENERIC
## library operators over the comptime value parameter N, with a COMPARISON-FREE carry/borrow
## ripple (the generate/propagate identity — avoids the unsigned-`<`/SIGNED-setcc latent
## miscompile). This program uses `u128` by its BARE prelude name (no local struct decl), proving
## the front-end resolves the ALIAS: construction (`u128(words = [lo, hi])`), field read, and the
## generic-operator route over the aliased type (the operand's `u128` canonicalizes to `uint(128)`).
##
## Four words exercise BOTH carry and borrow, correct AND incorrect directions:
##   carry add     : [MAX, 0]  + [1, 0]  = [0, 1]    r.words[1]=1  (never-carry -> 0)
##   non-carry add : [5, 6]    + [10, 20]= [15, 26]  p.words[1]=26 (always-carry -> 27)
##   borrow sub    : [0, 5]    - [1, 0]  = [MAX, 4]  g.words[1]=4  (never-borrow -> 5)
##   no-borrow sub : [30, 12]  - [8, 1]  = [22, 11]  m.words[1]=11 (spurious-borrow -> 10)
## 42 = r.w1 + p.w1 + g.w1 + m.w1 = 1 + 26 + 4 + 11. Any single carry/borrow bug misses 42.
main := fn() -> u64 {
  a := u128(words = [18446744073709551615, 0])
  b := u128(words = [1, 0])
  r := a + b

  c := u128(words = [5, 6])
  d := u128(words = [10, 20])
  p := c + d

  e := u128(words = [0, 5])
  f := u128(words = [1, 0])
  g := e - f

  h := u128(words = [30, 12])
  k := u128(words = [8, 1])
  m := h - k

  return r.words[1] + p.words[1] + g.words[1] + m.words[1]
}
