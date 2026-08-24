## selfhost::lexrt — the lexer, migrated onto the lean runtime `rt` (ROADMAP §1 capstone:
## the first pass moved off `alloc::vec` so the SELF-HOST lower can compile it, toward the
## TOOL-1 fixpoint). It reads the source `str` via the spec-canonical byte access `bytes(src)[i]`
## (a byte read under both compilers) and `src.len`, and stores each token as a 3-word arena
## RECORD `{kind, start, len}` (`rt::rec_set`) whose `usize` handle is pushed into a `rt::Vec`
## (path B — no `alloc::vec`, no `byte_at`, no multi-word element store). The downstream parser
## reads token `i` as `rt::rec_get(rt::vec_get(toks, i), field)`.
##
## Token kinds (a subset of `ast`'s scheme — the core the grammar needs): 0 EOF, 1 ident,
## 3 int, 5 `:=`, 6 `->`, 7 `::`, 8 `:`, 9 `,`, 10 `(`, 11 `)`, 12 `{`, 13 `}`, 14 `[`, 15 `]`,
## 16 `+`, 17 `-`, 18 `*`, 19 `/`, 20 `==`, 21 `=`, 22 `.`, 24 `<`, 25 `>`, 26 `<=`, 27 `>=`,
## 28 `!=`, 29 `%`, 30 `;`, 32 `?`, 33 `@`. (Strings/`..`/keyword-tagging follow.)
## The EIGHT compound-assignment glyphs of Grammar §3.2 are two-char tokens of their own so a
## statement head can be recognized: 40 `+=`, 41 `-=`, 44 `*=`, 45 `/=`, 47 `%=`, 48 `&=`,
## 49 `|=`, 50 `^=` (the last four were missing, so `x &= m` lexed as `&` then `=`, matched no
## statement head, and the STORE was silently dropped — a wrong value, I11).
## The sibling lean-runtime module `rt` (the lean runtime): its functions are called as
## `rt::…` and its types named `rt::Vec` / `rt::Arena` (the self-host parser skips param-type
## annotations; Stage-0 resolves the qualified type).

## Compare the source span `[start, start+length)` to the literal `lit`, byte by byte (via the
## spec byte access `bytes(...)[i]` — no `str_at`/`contains`, so it lowers under both compilers).
streq_src_lit := fn(src : str, start : usize, length : usize, lit : str) -> bool {
  if length != lit.len { return false }
  mut j := 0
  mut ok := true
  while j < length {
    if bytes(src)[start + j] != bytes(lit)[j] { ok = false }
    j += 1
  }
  return ok
}

## The token kind of an identifier span: 2 (keyword) if the lexeme is a v1 keyword, else 1.
## The keyword set mirrors `lexer.al`'s `is_kw` table; matched by explicit per-keyword
## `streq_src_lit` (not an array `contains`, which does not lower on the lean runtime).
kw_kind := fn(src : str, start : usize, length : usize) -> usize {
  if streq_src_lit(src, start, length, "fn") { return 2 }
  if streq_src_lit(src, start, length, "return") { return 2 }
  if streq_src_lit(src, start, length, "in") { return 2 }
  if streq_src_lit(src, start, length, "out") { return 2 }
  if streq_src_lit(src, start, length, "struct") { return 2 }
  if streq_src_lit(src, start, length, "enum") { return 2 }
  if streq_src_lit(src, start, length, "mut") { return 2 }
  if streq_src_lit(src, start, length, "if") { return 2 }
  if streq_src_lit(src, start, length, "else") { return 2 }
  if streq_src_lit(src, start, length, "match") { return 2 }
  if streq_src_lit(src, start, length, "while") { return 2 }
  if streq_src_lit(src, start, length, "for") { return 2 }
  if streq_src_lit(src, start, length, "comptime") { return 2 }
  if streq_src_lit(src, start, length, "pub") { return 2 }
  if streq_src_lit(src, start, length, "type") { return 2 }
  if streq_src_lit(src, start, length, "union") { return 2 }
  if streq_src_lit(src, start, length, "loop") { return 2 }
  if streq_src_lit(src, start, length, "defer") { return 2 }
  if streq_src_lit(src, start, length, "break") { return 2 }
  if streq_src_lit(src, start, length, "continue") { return 2 }
  if streq_src_lit(src, start, length, "unchecked") { return 2 }
  if streq_src_lit(src, start, length, "and") { return 2 }
  if streq_src_lit(src, start, length, "or") { return 2 }
  if streq_src_lit(src, start, length, "not") { return 2 }
  if streq_src_lit(src, start, length, "when") { return 2 }
  if streq_src_lit(src, start, length, "dyn") { return 2 }
  return 1
}

## Byte classifiers (the byte value is a `usize`, zero-extended from `bytes(src)[i]`).
is_space := fn(c : usize) -> bool { return c == 32 or c == 9 or c == 10 or c == 13 }
is_digit := fn(c : usize) -> bool { return c >= 48 and c <= 57 }
is_alpha := fn(c : usize) -> bool { return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 }
is_alnum := fn(c : usize) -> bool { return is_alpha(c) or is_digit(c) }

## Shared integer-literal machinery (Grammar §2.4). `parser::lit_val_at` is the located
## diagnostic wrapper; source scans use these pure primitives so they cannot grow a second,
## weaker decoder. The lexer keeps a prefixed literal's full alphanumeric/_ body in one token,
## allowing the validator to reject bad digits instead of truncating them.
pub lit_base := fn(s : str) -> usize {
  if s.len < 2 { return 10 }
  if bytes(s)[0] != 48 { return 10 }
  b1 := bytes(s)[1]
  if b1 == 120 or b1 == 88 { return 16 }
  if b1 == 111 or b1 == 79 { return 8 }
  if b1 == 98 or b1 == 66 { return 2 }
  10
}

pub digit_val := fn(c : usize) -> usize {
  if c >= 48 and c <= 57 { return c - 48 }
  if c >= 97 and c <= 102 { return c - 87 }
  if c >= 65 and c <= 70 { return c - 55 }
  99
}

is_hex_digit := fn(c : usize) -> bool {
  (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70)
}

## Decode only after int_lit_err has accepted the complete token. Keeping this total is
## useful to fail-loud callers: malformed text is never turned into a truncated value.
pub dec_val := fn(s : str) -> usize {
  n := s.len
  base := lit_base(s)
  mut v := 0
  mut i := 0
  if base != 10 { i = 2 }
  while i < n {
    c := bytes(s)[i]
    d := digit_val(c)
    if d < base { v = v * base + d }
    i += 1
  }
  v
}

## 0 well formed · 1 missing first digit after a prefix / leading `_` · 2 invalid digit ·
## 3 outside 64 bits · 4 uppercase base prefix. The boundary check never itself overflows.
pub int_lit_err := fn(s : str) -> usize {
  n := s.len
  base := lit_base(s)
  mut i := 0
  if base != 10 {
    if bytes(s)[1] == 88 or bytes(s)[1] == 79 or bytes(s)[1] == 66 { return 4 }
    i = 2
    if i >= n { return 1 }
    if bytes(s)[i] == 95 { return 1 }
  }
  mut lim : usize = 1844674407370955161
  mut rem : usize = 5
  if base == 16 { lim = 1152921504606846975 ; rem = 15 }
  else if base == 8 { lim = 2305843009213693951 ; rem = 7 }
  else if base == 2 { lim = 9223372036854775807 ; rem = 1 }
  mut v : usize = 0
  while i < n {
    c := bytes(s)[i]
    if c != 95 {
      d := digit_val(c)
      if d >= base { return 2 }
      if v > lim { return 3 }
      if v == lim and d > rem { return 3 }
      v = v * base + d
    }
    i += 1
  }
  0
}

## Validate a FLOAT literal token against Grammar §2.4. The lexer deliberately hands malformed
## exponent/hex-float tails to this gate as one kind-39 token, so `1e+`, `0x1.0`, and `0x1p+z`
## become located diagnostics instead of silently splitting into an integer plus identifiers. The
## underscore spelling is grammar-valid here; parser owns the existing backend boundary that rejects
## it before verbatim `.double` emission.
pub float_lit_err := fn(s : str) -> usize {
  n := s.len
  if n == 0 { return 1 }
  mut i := 0
  ## `hex-float ::= "0x" ( hex-digit { hex-digit | "_" } [ "." { hex-digit | "_" } ]
  ##                   | "." hex-digit { hex-digit | "_" } ) ( "p" | "P" ) [ "+" | "-" ] dec-int`
  if n >= 2 and bytes(s)[0] == 48 and bytes(s)[1] == 120 {
    i = 2
    mut have_mantissa := false
    if i < n and bytes(s)[i] == 46 {
      i += 1
      if i >= n or not is_hex_digit(bytes(s)[i]) { return 1 }
      have_mantissa = true
      while i < n and (is_hex_digit(bytes(s)[i]) or bytes(s)[i] == 95) { i += 1 }
    } else {
      if i >= n or not is_hex_digit(bytes(s)[i]) { return 1 }
      have_mantissa = true
      while i < n and (is_hex_digit(bytes(s)[i]) or bytes(s)[i] == 95) { i += 1 }
      if i < n and bytes(s)[i] == 46 {
        i += 1
        while i < n and (is_hex_digit(bytes(s)[i]) or bytes(s)[i] == 95) { i += 1 }
      }
    }
    if not have_mantissa { return 1 }
    if i >= n or (bytes(s)[i] != 112 and bytes(s)[i] != 80) { return 1 }
    i += 1
    if i < n and (bytes(s)[i] == 43 or bytes(s)[i] == 45) { i += 1 }
    if i >= n or not is_digit(bytes(s)[i]) { return 1 }
    while i < n and (is_digit(bytes(s)[i]) or bytes(s)[i] == 95) { i += 1 }
    if i != n { return 1 }
    return 0
  }
  ## Decimal forms: `dec-int "." dec-int [ exp ]` or `dec-int exp`.
  if not is_digit(bytes(s)[0]) { return 1 }
  while i < n and (is_digit(bytes(s)[i]) or bytes(s)[i] == 95) { i += 1 }
  mut has_dot := false
  mut has_exp := false
  if i < n and bytes(s)[i] == 46 {
    has_dot = true
    i += 1
    if i >= n or not is_digit(bytes(s)[i]) { return 1 }
    while i < n and (is_digit(bytes(s)[i]) or bytes(s)[i] == 95) { i += 1 }
  }
  if i < n and (bytes(s)[i] == 101 or bytes(s)[i] == 69) {
    has_exp = true
    i += 1
    if i < n and (bytes(s)[i] == 43 or bytes(s)[i] == 45) { i += 1 }
    if i >= n or not is_digit(bytes(s)[i]) { return 1 }
    while i < n and (is_digit(bytes(s)[i]) or bytes(s)[i] == 95) { i += 1 }
  }
  if not has_dot and not has_exp { return 1 }
  if i != n { return 1 }
  0
}

## Append a token record `{kind, start, len}` to the arena and push its handle into `toks`.
emit_tok := fn(in out toks : rt::Vec, in out ar : rt::Arena, kind : usize, start : usize, length : usize) -> usize {
  t := rt::bump(ar, 24)
  rt::rec_set(t, 0, kind)
  rt::rec_set(t, 1, start)
  rt::rec_set(t, 2, length)
  return rt::vec_push(toks, t)
}

## The byte at `i`, or 0 past the end (bounds-guarded peek).
peek := fn(src : str, i : usize, n : usize) -> usize {
  mut r := 0
  if i < n { r = bytes(src)[i] }
  return r
}

## Tokenize `src` into `toks` (token-handle records in `ar`); returns the token count
## (excluding the trailing EOF). Skips whitespace and `#` / `##` line comments.
## `base_off` is added to every emitted token `start` so the recorded spans are relative to the
## WHOLE source/buffer base the parser reads off (`str_at(pc.src + start)`): 0 for a single source,
## the region's offset for a module region inside a concatenated multi-module buffer. (`kw_kind`
## still uses the `src`-relative offset to read the lexeme bytes.)
pub lex_rt := fn(src : str, base_off : usize, in out toks : rt::Vec, in out ar : rt::Arena) -> usize {
  n := src.len
  mut i := 0
  mut nt := 0
  while i < n {
    b := bytes(src)[i]
    if is_space(b) {
      i += 1
    } else if b == 35 {
      ## `#` line comment (Grammar §2.5: `#` is a line comment, `##` a doc-comment —
      ## both skip to end of line; the doc distinction is cosmetic here since this
      ## lexer does not feed a comment side-channel to `fmt`). Matches the frozen
      ## Rust seed `b'#' => skip_comment()` (covers both `#` and `##`).
      mut g := true
      while g {
        if i >= n { g = false } else if bytes(src)[i] == 10 { g = false } else { i = i + 1 }
      }
    } else if b == 34 {
      ## a string literal — the token span COVERS the surrounding quotes (kind 4), matching
      ## lexer.al (the parser peels the inner bytes). Scan from the opening `"` to the next `"`.
      start := i
      i += 1
      mut g := true
      while g {
        ## A backslash (92) ESCAPES the next char — `\"` does NOT close the string, `\n`/`\\` are
        ## two-char sequences — so skip the escaped char too; otherwise `"\"\n"` (an escaped quote)
        ## terminates early at the inner `"` and the rest of the literal leaks into the token stream.
        if i >= n { g = false }
        else if bytes(src)[i] == 92 { i = i + 2 }
        else if bytes(src)[i] == 34 { i = i + 1; g = false }
        else { i = i + 1 }
      }
      e := emit_tok(toks, ar, 4, base_off + start, i - start)
      nt += 1
    } else if b == 39 {
      ## a CHAR literal `'c'` (kind 41) — the token span COVERS the surrounding single quotes; the
      ## parser decodes the inner byte(s) to the codepoint (`Expr::Num`). A backslash (92) ESCAPES the
      ## next byte (`'\n'`/`'\\'`/`'\''`), so skip the escaped byte before looking for the closing `'`.
      start := i
      i += 1
      mut g := true
      while g {
        if i >= n { g = false }
        else if bytes(src)[i] == 92 { i = i + 2 }
        else if bytes(src)[i] == 39 { i = i + 1; g = false }
        else { i = i + 1 }
      }
      e := emit_tok(toks, ar, 41, base_off + start, i - start)
      nt += 1
    } else if is_alpha(b) {
      start := i
      mut g := true
      while g {
        if i >= n { g = false } else if is_alnum(bytes(src)[i]) { i = i + 1 } else { g = false }
      }
      e := emit_tok(toks, ar, kw_kind(src, start, i - start), base_off + start, i - start)
      nt += 1
    } else if is_digit(b) {
      start := i
      ## A digit run that STARTS right after a `.` is a TUPLE INDEX (`t.0`, and the second `0` of
      ## `t.0.0`) — grammar §2.4 `tuple-index ::= digit { digit }`: PLAIN decimal, no `_` separator
      ## and no base prefix. Computed BEFORE the scan so both the prefix test and the separator test
      ## below can exclude it (`t.0` must never eat a following `b`/`x`/`o` or `_`).
      prev_dot := start > 0 and bytes(src)[start - 1] == 46
      ## BASE-PREFIXED integer (grammar §2.4) — `0x…` hex, `0o…` octal, `0b…` binary, consumed as a
      ## single integer token (kind 3); the shared `dec_val` helper decodes it. Detected before the decimal run
      ## so the prefix letter doesn't terminate the number (which used to split `0xFF` into `0` + the
      ## ident `xFF`, and — the silent-wrong-value defect this fixes — `0b1000` into `0` + `b1000`,
      ## `0o777` into `0` + `o777`, so the literal's VALUE became plain `0` with no diagnostic).
      ## The BODY is consumed greedily as `[0-9A-Za-z_]*`, i.e. INCLUDING characters that are not
      ## digits of that base and including `_` separators: the shared `int_lit_err` then validates the
      ## whole token and REJECTS it located. Greedy lexing is exactly what turns `0b12` / `0xZ` /
      ## `0x_1` from a silent truncation into a diagnostic — the lexer has no diagnostic channel of
      ## its own, so it hands the parser a complete token to judge.
      pfx1 := if i + 1 < n { bytes(src)[i + 1] } else { 0 }
      is_pfx := (not prev_dot) and b == 48 and (pfx1 == 120 or pfx1 == 88 or pfx1 == 111 or pfx1 == 79 or pfx1 == 98 or pfx1 == 66)
      if is_pfx {
        ## C-style HEX FLOATS are a distinct token from hex integers. The `p`/`P` exponent is
        ## mandatory; a dot without it is still consumed as a float candidate so the parser can
        ## reject `0x1.0` in one located diagnostic instead of splitting it into `0x1`, `.`, `0`.
        ## Uppercase `0X` remains the invalid integer-prefix path below; Grammar §2.4 spells the
        ## hex-float prefix as lowercase `0x`.
        mut hex_float := false
        if pfx1 == 120 {
          mut j := i + 2
          mut hex_mantissa := false
          mut hex_dot := false
          if j < n and bytes(src)[j] == 46 {
            hex_dot = true
            j += 1
            if j < n and is_hex_digit(bytes(src)[j]) {
              hex_mantissa = true
              while j < n and (is_hex_digit(bytes(src)[j]) or bytes(src)[j] == 95) { j += 1 }
            }
          } else if j < n and is_hex_digit(bytes(src)[j]) {
            hex_mantissa = true
            while j < n and (is_hex_digit(bytes(src)[j]) or bytes(src)[j] == 95) { j += 1 }
            if j < n and bytes(src)[j] == 46 {
              hex_dot = true
              j += 1
              while j < n and (is_hex_digit(bytes(src)[j]) or bytes(src)[j] == 95) { j += 1 }
            }
          }
          if hex_mantissa and (hex_dot or (j < n and (bytes(src)[j] == 112 or bytes(src)[j] == 80))) {
            hex_float = true
            i = j
            if i < n and (bytes(src)[i] == 112 or bytes(src)[i] == 80) {
              i += 1
              if i < n and (bytes(src)[i] == 43 or bytes(src)[i] == 45) { i += 1 }
              while i < n and (is_digit(bytes(src)[i]) or bytes(src)[i] == 95) { i += 1 }
            }
            ## Keep a glued alphabetic/underscore tail in the same token for float_lit_err.
            mut ht := true
            while ht {
              if i >= n { ht = false } else if is_alnum(bytes(src)[i]) { i += 1 } else { ht = false }
            }
          }
        }
        if hex_float {
          eh := emit_tok(toks, ar, 39, base_off + start, i - start)
          nt += 1
        } else {
          i += 2                                 ## '0x' / '0o' / '0b'
          mut gh := true
          while gh {
            if i >= n { gh = false } else {
              hc := bytes(src)[i]
              if is_alnum(hc) { i = i + 1 } else { gh = false }
            }
          }
          eh := emit_tok(toks, ar, 3, base_off + start, i - start)
          nt += 1
        }
      } else {
      ## DECIMAL `dec-int ::= digit { digit | "_" }` (grammar §2.4) — `_` is a non-significant digit
      ## separator (SYN-3), so it must stay INSIDE the token: stopping at it silently truncated
      ## `1_000` to `1` and `9_223_372_036_854_775_808` to `9`. A `tuple-index` takes no separator,
      ## hence the `prev_dot` exclusion (a literal can never START with `_` — this branch is entered
      ## on a digit).
      mut g := true
      while g {
        if i >= n { g = false } else {
          dc := bytes(src)[i]
          if is_digit(dc) or ((not prev_dot) and dc == 95) { i = i + 1 } else { g = false }
        }
      }
      ## FLOAT literal — a `.` immediately followed by a digit continues the number as a float
      ## (`1.5`), and `e`/`E` starts the decimal exponent forms (`1e10`, `1.5E-2`). NOT `1..5`
      ## (a `..` range — the second char is `.`) and NOT a trailing `1.` (no fractional digit).
      ## A malformed exponent is still one kind-39 token; parser::float_lit_err rejects it located.
      ## The source span stays verbatim so decimal exponent spelling reaches `.double` unchanged.
      mut tkind := 3                       ## integer
      ## A tuple index (`prev_dot`, computed above) is NOT the integer part of a float — do NOT
      ## extend it across a following `.digit` (else `t.0.0` greedily lexes `0.0` as one float token
      ## and the tuple double-index mis-parses). A genuine float `1.5` is never preceded by `.`, so
      ## this is exact.
      if (not prev_dot) and i + 1 < n and bytes(src)[i] == 46 and is_digit(bytes(src)[i + 1]) {
        i += 1                                 ## '.'
        mut gf := true
        while gf {
          if i >= n { gf = false } else if is_digit(bytes(src)[i]) or bytes(src)[i] == 95 { i = i + 1 } else { gf = false }
        }
        tkind = 39                                ## float
      }
      ## A decimal exponent is part of the same float token even when malformed, so `1e+` and
      ## `1efoo` cannot silently become an integer followed by identifiers. The optional sign is
      ## consumed only here; a later `+`/`-` remains an ordinary expression operator.
      if (not prev_dot) and i < n and (bytes(src)[i] == 101 or bytes(src)[i] == 69) {
        i += 1
        if i < n and (bytes(src)[i] == 43 or bytes(src)[i] == 45) { i += 1 }
        mut ge := true
        while ge {
          if i >= n { ge = false } else if is_digit(bytes(src)[i]) or bytes(src)[i] == 95 { i += 1 } else { ge = false }
        }
        mut et := true
        while et {
          if i >= n { et = false } else if is_alnum(bytes(src)[i]) { i += 1 } else { et = false }
        }
        tkind = 39
      }
      e := emit_tok(toks, ar, tkind, base_off + start, i - start)
      nt += 1
      }
    } else {
      ## operators / punctuation — two-char forms first, then single. Each branch sets ONLY
      ## `kind` (a single statement, so the brace body needs no `;`/newline separator — which the
      ## two compilers disagree on); the width `w` is derived from the two-char kinds afterwards.
      c1 := peek(src, i + 1, n)
      c2 := peek(src, i + 2, n)
      mut kind := 23                  ## 23 = other (unrecognized single byte)
      if b == 58 and c1 == 61 { kind = 5 }               ## `:=`
      else if b == 58 and c1 == 58 { kind = 7 }          ## `::`
      else if b == 58 { kind = 8 }                       ## `:`
      else if b == 45 and c1 == 62 { kind = 6 }          ## `->`
      else if b == 61 and c1 == 61 { kind = 20 }         ## `==`
      else if b == 61 and c1 == 62 { kind = 38 }         ## `=>`
      else if b == 60 and c1 == 61 { kind = 26 }         ## `<=`
      else if b == 62 and c1 == 61 { kind = 27 }         ## `>=`
      else if b == 33 and c1 == 61 { kind = 28 }         ## `!=`
      else if b == 46 and c1 == 46 and c2 == 61 { kind = 37 } ## `..=`
      else if b == 46 and c1 == 46 { kind = 31 }         ## `..`
      else if b == 61 { kind = 21 }                      ## `=`
      else if b == 44 { kind = 9 }                       ## `,`
      else if b == 40 { kind = 10 }                      ## `(`
      else if b == 41 { kind = 11 }                      ## `)`
      else if b == 123 { kind = 12 }                     ## `{`
      else if b == 125 { kind = 13 }                     ## `}`
      else if b == 91 { kind = 14 }                      ## `[`
      else if b == 93 { kind = 15 }                      ## `]`
      else if b == 43 and c1 == 61 { kind = 40 }          ## `+=`
      else if b == 45 and c1 == 61 { kind = 41 }          ## `-=`
      else if b == 42 and c1 == 61 { kind = 44 }          ## `*=`
      else if b == 47 and c1 == 61 { kind = 45 }          ## `/=`
      else if b == 37 and c1 == 61 { kind = 47 }          ## `%=`
      else if b == 38 and c1 == 61 { kind = 48 }          ## `&=`
      else if b == 124 and c1 == 61 { kind = 49 }         ## `|=`
      else if b == 94 and c1 == 61 { kind = 50 }          ## `^=`
      else if b == 43 { kind = 16 }                      ## `+`
      else if b == 45 { kind = 17 }                      ## `-`
      else if b == 42 { kind = 18 }                      ## `*`
      else if b == 47 { kind = 19 }                      ## `/`
      else if b == 46 { kind = 22 }                      ## `.`
      else if b == 60 { kind = 24 }                      ## `<`
      else if b == 62 { kind = 25 }                      ## `>`
      else if b == 37 { kind = 29 }                      ## `%`
      else if b == 59 { kind = 30 }                      ## `;`
      else if b == 63 { kind = 32 }                      ## `?`
      else if b == 64 { kind = 33 }                      ## `@`
      else if b == 38 { kind = 34 }                      ## `&`
      else if b == 124 { kind = 35 }                     ## `|`
      else if b == 94 { kind = 36 }                      ## `^`
      else if b == 126 { kind = 46 }                     ## `~` (bitwise NOT, unary prefix)
      mut w := 1
      if kind == 5 or kind == 6 or kind == 7 or kind == 20 or kind == 26 or kind == 27 or kind == 28 or kind == 38 or kind == 31 or kind == 40 or kind == 41 or kind == 44 or kind == 45 or kind == 47 or kind == 48 or kind == 49 or kind == 50 { w = 2 }
      if kind == 37 { w = 3 }
      e := emit_tok(toks, ar, kind, base_off + i, w)
      nt += 1
      i += w
    }
  }
  ze := emit_tok(toks, ar, 0, base_off + n, 0)          ## EOF token
  return nt
}
