## e2e — TYP-10 slice B: GENERIC OPERATORS over a comptime VALUE parameter (Comptime §10,
## operators.md OP-1). The SAME `@inline` operator serves every instantiation of the generic
## type-function `uint := fn(comptime N : u64) -> type { struct { words : [u64; N/64] } }`
## (slice A): the operator's first parameter is a comptime VALUE param `N`, its two value
## operands are `uint(N)`, and the operator ROUTES when the base head of its first value-param
## type (`uint` in `uint(N)`) equals the operand's base head (`uint` in `uint(192)`), binding
## `N` from the operand's value argument. The body then expands AT THE SITE with `N` bound, so
## the `comptime for i in 0 .. N/64` ripple unfolds per width: `uint(128)` and `uint(192)`
## sites in one program each expand with their own `N` (per-instance expansion, no symbol).
##
## `+` is a comparison-free ripple-carry over the words (the u128 recipe, generalized): per
## word, `s1 = a+b` (wrapping, `unchecked` — the carry must not trap under I11), the carry OUT
## is bit 63 of `(a&b) | ((a|b) & ~s1)` (the generate/propagate identity, no `<` anywhere), then
## the incoming carry is added with the SAME identity and the two carries OR-ed. `==` is the
## OR of the per-word XORs compared to zero. Both bounds (`N/64`) fold against the binding.
##
## Carry-across-a-word-boundary verification at TWO widths in one program:
##   uint(192): {2^64-1, 0, 0} + {1, 0, 0} = {0, 1, 0}   (word 0 wraps -> +1 into word 1)
##   uint(128): {2^64-1, 0}    + {1, 0}    = {0, 1}      (a SECOND instance of the same ops)
## A missed route (scalar fall-through over the words) or a dropped carry fails the `==`
## checks. 42 = both checks pass; 1/2 = the 192/128 check failed.
uint := fn(comptime N : u64) -> type { struct { words : [u64; N/64] } }

@inline + := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N) {
  mut r : uint(N) = a
  mut carry : u64 = 0
  comptime for i in 0 .. N/64 {
    s1 := unchecked { a.words[i] + b.words[i] }
    c1 := unchecked { ((a.words[i] & b.words[i]) | ((a.words[i] | b.words[i]) & ~s1)).shr(63) }
    s2 := unchecked { s1 + carry }
    c2 := unchecked { ((s1 & carry) | ((s1 | carry) & ~s2)).shr(63) }
    r.words[i] = s2
    carry = c1 | c2
  }
  return r
}

@inline == := fn(comptime N : u64, a : uint(N), b : uint(N)) -> bool {
  mut d : u64 = 0
  comptime for i in 0 .. N/64 {
    d = d | (a.words[i] ^ b.words[i])
  }
  return d == 0
}

main := fn() -> u64 {
  mut x : uint(192) = uint(192)(words = [18446744073709551615, 0, 0])
  mut y : uint(192) = uint(192)(words = [1, 0, 0])
  z := x + y
  mut w : uint(192) = uint(192)(words = [0, 1, 0])
  if (z == w) == false { return 1 }
  p := uint(128)(words = [18446744073709551615, 0]) + uint(128)(words = [1, 0])
  mut q : uint(128) = uint(128)(words = [0, 1])
  if p == q { return 42 }
  2
}
