## u128 — the TYP-10 GENERALIZED `uint(N)` recipe: a wider-than-native unsigned integer of N bits
## (N a POSITIVE MULTIPLE OF 64 — the comptime array-length fold rejects anything else LOUD, see
## `lower_layout::ct_arr_len`), as an ORDINARY LIBRARY multiword type (Types §3 / §7
## "Wider-than-native named integers"; TYP-2 / TYP-10 / D23 / D24). `uint` is a comptime-VALUE
## type-function: `uint(N)` is a nominal struct of `N/64` little-endian `u64` words (word 0 = the
## least-significant 64 bits, §6 declaration-order layout). The FULL operator set (`+ - * / %` +
## the six comparisons) is `@inline` GENERIC operators over the comptime value parameter N — the
## TYP-10 slice-B route (the first value-param's base head `uint` matches the operand's base head,
## N binds from the operand's value argument, the body expands PER SITE with `comptime for` bounds
## folded against the binding). Arithmetic is library code with VISIBLE cost, NOT a compiler
## built-in and NOT backend register-pair magic. This module is ambiently injected into a
## single-file compile that references `u128` by bare name OR instantiates a bare `uint(` (cli.al
## `ambient_paths`); dormant for the self-host build (`src/` never mentions either outside
## comments), so the TOOL-1 fixpoint is unaffected.
uint := fn(comptime N : u64) -> type { struct { words : [u64; N/64] } }

## `u128 ≡ uint(128)` (Types §7) — a type ALIAS as a plain value decl: the parser records the
## `ident(…)` RHS span in the decl's `alias_ts`/`alias_tl`, and every type-position consumer
## canonicalizes the bare name back to the full instance span: `lower_layout::alias_rhs` feeds
## `ct_arr_len` (layout — the bare `u128` carries no `(128)` in source) and the lower's
## generic-operator route (`generic_op_decl_idx`'s operand head + `op_ct_bind`'s N binding). As a
## VALUE the binding is never referenced (construction and type positions resolve the alias to the
## struct decl), so it emits nothing; an unused value binding is inert everywhere else.
u128 := uint(128)

## `+` — modular per-word add with a COMPARISON-FREE carry. Per word, `s1 = a+b` (wrapping,
## `unchecked` — the carry must not trap under the I11/CG-8 overflow guard), the carry OUT is bit
## 63 of `(a&b) | ((a|b) & ~s1)` (the generate/propagate identity, no `<` anywhere), then the
## incoming carry is added with the SAME identity and the two carries OR-ed. `comptime for i in
## 0 .. N/64` folds against the site's N binding, so one operator serves every width.
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

## `-` — modular per-word subtract, the SAME ripple over `a + ~b + 1` (the two's-complement
## negate): carry-IN 1 with the per-word add of `~(b.words[i])` computes `a - b` mod 2^N exactly;
## the final carry (1 = no borrow) is discarded. Comparison-free, like `+`. `~` MUST parenthesize
## its index operand — prefix `~` binds tighter than the postfix, so `~(b.words[i])`, never
## `~b.words[i]` (that would bitnot the whole aggregate, then index).
@inline - := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N) {
  mut r : uint(N) = a
  mut carry : u64 = 1
  comptime for i in 0 .. N/64 {
    nb := ~(b.words[i])
    s1 := unchecked { a.words[i] + nb }
    c1 := unchecked { ((a.words[i] & nb) | ((a.words[i] | nb) & ~s1)).shr(63) }
    s2 := unchecked { s1 + carry }
    c2 := unchecked { ((s1 & carry) | ((s1 | carry) & ~s2)).shr(63) }
    r.words[i] = s2
    carry = c1 | c2
  }
  return r
}

## `*` — schoolbook multiply keeping the LOW N bits (modular, per D24), O(words²). COLUMN k of the
## product receives the LOW half of every `a[i]·b[j]` with i+j = k and the HIGH half of every one
## with i+j = k-1, plus the carry column k-1 produced. The column accumulates mod 2^64 — each
## wrapping add's carry-out (≤ 1) is COUNTED into the next column's incoming carry (their sum is
## < 2^64, so no bit is lost); the final accumulator is the result word. All adds wrap (`unchecked`
## — the reduction IS the modular semantics, else the I11 guard would trap instead of reduce). The
## per-word HIGH half is x86_64's 1-operand `mulq` (high half in %rdx) via the synthetic `mulhiq`
## intrinsic (Assembly §80 / D25.3) under `comptime if target.arch == Arch.x86_64`, INLINED in the
## body — a helper fn with a comptime param is not declarable (TYP-10 v1). The triangular guards
## `i <= k` / `i < k` are runtime ifs on the unrolled loop vars (each holds its constant); the
## `comptime for` bounds (`N/64`) fold against the site binding.
@inline * := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N) {
  mut r : uint(N) = a
  comptime for w in 0 .. N/64 { r.words[w] = 0 }
  mut carry : u64 = 0
  comptime for k in 0 .. N/64 {
    mut acc : u64 = carry
    mut nc : u64 = 0
    comptime for i in 0 .. N/64 {
      if i <= k {
        lo := unchecked { a.words[i] * b.words[k - i] }
        s := unchecked { acc + lo }
        c := unchecked { ((acc & lo) | ((acc | lo) & ~s)).shr(63) }
        acc = s
        nc = unchecked { nc + c }
      }
      if i < k {
        mut hi : u64 = a.words[i]
        comptime if target.arch == Arch.x86_64 { x86_64.mulhiq(hi, b.words[k - 1 - i]) }
        s := unchecked { acc + hi }
        c := unchecked { ((acc & hi) | ((acc | hi) & ~s)).shr(63) }
        acc = s
        nc = unchecked { nc + c }
      }
    }
    r.words[k] = acc
    carry = nc
  }
  return r
}

## `/` — quotient by binary LONG DIVISION (shift-subtract), COMPTIME-UNROLLED over the N bits: an
## `@inline` operator body cannot hold a runtime `while` (the inline expander has no loop form) and
## a comptime-param helper fn is not declarable, so the loop is `comptime for i in 0 .. N` with the
## whole step self-contained in the body. Per step, MSB→LSB: the running remainder shifts left one
## bit across the words and pulls in the next dividend bit (the bit position is tracked by the
## runtime locals `widx`/`boff`, counted down from (N/64-1, 63) — N itself is comptime-only, not a
## runtime value); the conditional subtract `if r >= b { r -= b; set quotient bit }` is
## COMPARISON-FREE — the borrow ripple's final carry IS `r >= b`, it becomes an all-ones mask
## (`0 - carry`), and subtracting `b & mask` is the branchless select; the carry bit itself,
## shifted to the step's position, is the quotient bit. Division by zero is a checked trap (I11),
## matching num.al's scalar `/`.
@inline / := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N) {
  mut z : u64 = 0
  comptime for w in 0 .. N/64 { z = z | b.words[w] }
  comptime if verify.checked {
    if z == 0 { panic("uint(N) division by zero") }
  }
  mut q : uint(N) = a
  mut r : uint(N) = a
  comptime for w in 0 .. N/64 {
    q.words[w] = 0
    r.words[w] = 0
  }
  mut widx : u64 = 0
  comptime for w in 1 .. N/64 { widx = unchecked { widx + 1 } }
  mut boff : u64 = 63
  comptime for i in 0 .. N {
    mut cin : u64 = 0
    comptime for w in 0 .. N/64 {
      top := r.words[w].shr(63)
      r.words[w] = unchecked { r.words[w].shl(1) | cin }
      cin = top
    }
    r.words[0] = r.words[0] | (unchecked { a.words[widx].shr(boff) } & 1)
    mut cry : u64 = 1
    comptime for w in 0 .. N/64 {
      nb := ~(b.words[w])
      s1 := unchecked { r.words[w] + nb }
      c1 := unchecked { ((r.words[w] & nb) | ((r.words[w] | nb) & ~s1)).shr(63) }
      s2 := unchecked { s1 + cry }
      c2 := unchecked { ((s1 & cry) | ((s1 | cry) & ~s2)).shr(63) }
      cry = c1 | c2
    }
    mask := unchecked { 0 - cry }
    mut cry2 : u64 = 1
    comptime for w in 0 .. N/64 {
      sb := b.words[w] & mask
      nb2 := ~sb
      t1 := unchecked { r.words[w] + nb2 }
      d1 := unchecked { ((r.words[w] & nb2) | ((r.words[w] | nb2) & ~t1)).shr(63) }
      t2 := unchecked { t1 + cry2 }
      d2 := unchecked { ((t1 & cry2) | ((t1 | cry2) & ~t2)).shr(63) }
      r.words[w] = t2
      cry2 = d1 | d2
    }
    q.words[widx] = q.words[widx] | cry.shl(boff)
    ## advance (widx, boff) down one bit — the word advance fires ONLY when boff was already 0
    ## (an `else`: sequential `if`s would fire the reset in the same step the decrement reaches 0).
    if boff == 0 {
      widx = unchecked { widx - 1 }
      boff = 63
    } else {
      boff = unchecked { boff - 1 }
    }
  }
  return q
}

## `%` — remainder by the SAME comptime-unrolled shift-subtract loop, yielding the final running
## remainder (the quotient bits are not tracked). A checked div-by-zero trap, like `/`.
@inline % := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N) {
  mut z : u64 = 0
  comptime for w in 0 .. N/64 { z = z | b.words[w] }
  comptime if verify.checked {
    if z == 0 { panic("uint(N) remainder by zero") }
  }
  mut r : uint(N) = a
  comptime for w in 0 .. N/64 { r.words[w] = 0 }
  mut widx : u64 = 0
  comptime for w in 1 .. N/64 { widx = unchecked { widx + 1 } }
  mut boff : u64 = 63
  comptime for i in 0 .. N {
    mut cin : u64 = 0
    comptime for w in 0 .. N/64 {
      top := r.words[w].shr(63)
      r.words[w] = unchecked { r.words[w].shl(1) | cin }
      cin = top
    }
    r.words[0] = r.words[0] | (unchecked { a.words[widx].shr(boff) } & 1)
    mut cry : u64 = 1
    comptime for w in 0 .. N/64 {
      nb := ~(b.words[w])
      s1 := unchecked { r.words[w] + nb }
      c1 := unchecked { ((r.words[w] & nb) | ((r.words[w] | nb) & ~s1)).shr(63) }
      s2 := unchecked { s1 + cry }
      c2 := unchecked { ((s1 & cry) | ((s1 | cry) & ~s2)).shr(63) }
      cry = c1 | c2
    }
    mask := unchecked { 0 - cry }
    mut cry2 : u64 = 1
    comptime for w in 0 .. N/64 {
      sb := b.words[w] & mask
      nb2 := ~sb
      t1 := unchecked { r.words[w] + nb2 }
      d1 := unchecked { ((r.words[w] & nb2) | ((r.words[w] | nb2) & ~t1)).shr(63) }
      t2 := unchecked { t1 + cry2 }
      d2 := unchecked { ((t1 & cry2) | ((t1 | cry2) & ~t2)).shr(63) }
      r.words[w] = t2
      cry2 = d1 | d2
    }
    if boff == 0 {
      widx = unchecked { widx - 1 }
      boff = 63
    } else {
      boff = unchecked { boff - 1 }
    }
  }
  return r
}

## The three BIT-glyph operators `&` / `|` / `^` (OP-1, TYP-10; operators.md): a per-word bitwise
## fold over the little-endian words — a bit op is independent per lane, so there is NO carry or
## cross-word ripple (unlike `+`/`-`/`*`). Each `@inline` generic operator's `comptime for i in 0
## .. N/64` folds against the site's N binding, so one operator serves every width. The scalar
## per-word `&`/`|`/`^` are the native `u64` bit ops (num.al) — no I11 guard applies to a pure bit
## op. src/ declares no glyph-bitwise operator fn, so these are dormant for the self-host build
## (the parser name-gate admits the `&`/`|`/`^` names but no src/ decl uses them) → fixpoint-neutral.
@inline & := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N) {
  mut r : uint(N) = a
  comptime for i in 0 .. N/64 {
    r.words[i] = a.words[i] & b.words[i]
  }
  return r
}
@inline | := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N) {
  mut r : uint(N) = a
  comptime for i in 0 .. N/64 {
    r.words[i] = a.words[i] | b.words[i]
  }
  return r
}
@inline ^ := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N) {
  mut r : uint(N) = a
  comptime for i in 0 .. N/64 {
    r.words[i] = a.words[i] ^ b.words[i]
  }
  return r
}

## The six comparisons (OP-1, §4.3a), hi-word-to-lo-word lexicographic UNSIGNED. `<` is computed
## COMPARISON-FREE: `a < b` iff the `a - b` borrow ripple (the `-` recipe: `a + ~b + 1`) yields NO
## final carry — equivalent to the lexicographic compare, and immune to any signed-`setcc` pitfall
## by construction. `==` is the OR of the per-word XORs compared to zero. `!=`/`>`/`<=`/`>=` are
## the nested generic routes (`==`/`<` over the same instance — TYP-10 slice B: a generic operator
## body may use another generic operator over the same type). They yield `bool`, usable in a
## condition or a value position, and OVERRIDE any structural derive (which, comparing the
## declaration-order LOW word first, would be WRONG for a wide integer).
@inline == := fn(comptime N : u64, a : uint(N), b : uint(N)) -> bool {
  mut d : u64 = 0
  comptime for i in 0 .. N/64 {
    d = d | (a.words[i] ^ b.words[i])
  }
  return d == 0
}
@inline != := fn(comptime N : u64, a : uint(N), b : uint(N)) -> bool {
  return (a == b) == false
}
@inline < := fn(comptime N : u64, a : uint(N), b : uint(N)) -> bool {
  mut cry : u64 = 1
  comptime for i in 0 .. N/64 {
    nb := ~(b.words[i])
    s1 := unchecked { a.words[i] + nb }
    c1 := unchecked { ((a.words[i] & nb) | ((a.words[i] | nb) & ~s1)).shr(63) }
    s2 := unchecked { s1 + cry }
    c2 := unchecked { ((s1 & cry) | ((s1 | cry) & ~s2)).shr(63) }
    cry = c1 | c2
  }
  return cry == 0
}
@inline > := fn(comptime N : u64, a : uint(N), b : uint(N)) -> bool {
  return b < a
}
@inline <= := fn(comptime N : u64, a : uint(N), b : uint(N)) -> bool {
  return (b < a) == false
}
@inline >= := fn(comptime N : u64, a : uint(N), b : uint(N)) -> bool {
  return (a < b) == false
}
