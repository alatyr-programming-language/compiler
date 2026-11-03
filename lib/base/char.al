## `char` — a Unicode code point, a **brand** over `u32` (the kernel keeps
## no built-in code-point type; `char` is a prelude type over a raw block). `u32(c)`
## and `char(n)` cross between them; `==`/`<` lower as the unsigned `u32` compares.
pub char := brand(u32)

## `char(n)` — checked code-point construction (Stdlib 3.2, I11): `n` must be a valid
## Unicode scalar value (at most 0x10FFFF and not a surrogate 0xD800..=0xDFFF), else a
## defined trap. A library conversion-constructor (`@convert`, 4.6) — no built-in
## code-point range. The validity guard is mode-dependent: present in checked
## code, dropped under `unchecked` (a raw reinterpret there).
##
## `pub`, per §4.6 "Scope, not coherence" — "A `@convert` is an ordinary `pub` binding, found
## by the name-resolution rules in effect at the call site" — and TYP-14's recorded stdlib
## consequence: "The stdlib's `to_char` becomes `pub` (an unimportable conversion is not 'in
## scope' for anyone, so option 1 would be inert otherwise)" (spec `730486f`, released 1.7.0;
## compiler#364). Measured on the parent, `base::char::to_char(65)` was refused by `check`.
pub to_char := @convert fn(n : u32) -> char {
  comptime if verify.checked {
    ## §3.2 requires this guard to fail through `trap()` — the same instruction as the built-in
    ## narrowing guard (§4.1, CG-13), never `panic`. `trap()` is not yet a callable prelude
    ## intrinsic: a call to it emits a reference to `<module>__trap` that no definition answers,
    ## so every program linking this module fails at `ld`. #1427 records that gap; until it is
    ## fixed the guard stays on `panic` as a named blocker, not as the chosen form.
    if n > 1114111 { panic("invalid code point") }
    if n >= 55296 and n <= 57343 { panic("surrogate code point") }
  }
  unchecked bitcast(char, n)
}

## `char` classification predicates (Stdlib §3.2) — the ASCII tests a lexer/parser
## needs (digit / alpha / alphanumeric / whitespace). A `char` is a Unicode code
## point (`u32`-shaped, not a byte); each predicate reads the code-point value with
## the explicit `u32(c)` conversion (§4.2) and tests the ASCII range. Unicode-general
## classification (the full property tables) is an additive later increment — these
## cover ASCII source text, which the v1 compiler's own lexer is written in.

## A decimal digit `0`–`9`.
pub is_digit := fn(c : char) -> bool {
  n := u32(c)
  n >= 48 and n <= 57
}

## An ASCII letter `a`–`z` or `A`–`Z`.
pub is_alpha := fn(c : char) -> bool {
  n := u32(c)
  lower := n >= 97 and n <= 122
  upper := n >= 65 and n <= 90
  lower or upper
}

## An ASCII letter or decimal digit.
pub is_alnum := fn(c : char) -> bool {
  is_alpha(c) or is_digit(c)
}

## ASCII whitespace: space, tab, newline, carriage return, vertical tab, form feed.
pub is_whitespace := fn(c : char) -> bool {
  n := u32(c)
  if n == 32 { return true }
  n >= 9 and n <= 13
}

## A hexadecimal digit `0`–`9`, `a`–`f`, or `A`–`F` — the lexer's `0x…` literals.
pub is_hex_digit := fn(c : char) -> bool {
  if is_digit(c) { return true }
  n := u32(c)
  lower := n >= 97 and n <= 102
  upper := n >= 65 and n <= 70
  lower or upper
}

## ASCII **lower-case** folding: map `A`–`Z` to `a`–`z`; every other code point is
## returned unchanged (Stdlib §3.2 — ASCII only; Unicode case folding is additive).
pub to_lower := fn(c : char) -> char {
  n := u32(c)
  if n >= 65 and n <= 90 {
    return char(n + 32)
  }
  c
}

## ASCII **upper-case** folding: map `a`–`z` to `A`–`Z`; every other code point is
## returned unchanged (Stdlib §3.2 — ASCII only).
pub to_upper := fn(c : char) -> char {
  n := u32(c)
  if n >= 97 and n <= 122 {
    return char(n - 32)
  }
  c
}

## The numeric value `0`–`15` of a hexadecimal digit (`0`–`9` / `a`–`f` / `A`–`F`),
## or `None` for any other code point — the per-digit primitive a lexer folds over
## a `0x…` literal (Stdlib §3.2).
pub hex_value := fn(c : char) -> Option(u32) {
  n := u32(c)
  if n >= 48 and n <= 57 {
    return Option(u32).Some(n - 48)
  }
  if n >= 97 and n <= 102 {
    return Option(u32).Some(n - 97 + 10)
  }
  if n >= 65 and n <= 70 {
    return Option(u32).Some(n - 65 + 10)
  }
  Option(u32).None
}
