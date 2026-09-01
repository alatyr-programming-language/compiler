## `str` — a slice of validated UTF-8 bytes (`[u8]`), Stdlib §3.6. Its runtime
## representation is the same `{ ptr, len }` pair as a slice (Type System §7);
## the bytes themselves live in read-only data. Length is reported in **explicit
## units** — byte ≠ code point is named, not hidden.
##
## Byte indexing `s[i]` (a `u8`) and sub-slicing `s[a..b]` (a `str`) come from
## the shared slice machinery (§3.5). `chars` (the `CharIter` code-point iterator)
## and `codepoint_count` (an O(n) lead-byte count) are below.

## `byte_len` — the length in **bytes** (O(1)); not the code-point count (§3.6).
pub byte_len := fn(s : str) -> usize { return s.len }

## `codepoint_count` — the number of Unicode **code points** (§3.6): O(n), counting
## UTF-8 **lead** bytes (a continuation byte is `0x80..=0xBF` — top two bits `10`;
## written arithmetically, `128..192`, as the decoder does). Distinct from
## `byte_len` (the O(1) byte count) — byte ≠ code point is named, not hidden.
pub codepoint_count := fn(s : str) -> usize {
  bs := bytes(s)
  mut n : usize = 0
  mut i : usize = 0
  while i < s.len {
    b := bs[i]
    if b < 128 or b >= 192 { n = n + 1 }
    i += 1
  }
  n
}

## `bytes` — the underlying bytes as a `[u8]` slice (§3.6): the same pointer and
## length, viewed as a plain byte slice.
pub bytes := fn(s : str) -> Slice(u8) { return Slice(u8)(ptr = s.ptr, len = s.len) }

## `str_at` — a `str` **view** over the `n` raw bytes at address `p` (§3.6): the raw
## inverse of `bytes`, encapsulating the `usize → ptr(u8) → Slice(u8) → str`
## reinterpretation so a caller scanning a byte buffer by address (a lexer reading
## `base + offset`) names a lexeme in **one** step instead of three. **Unchecked**: the
## bytes are assumed valid UTF-8 and the view aliases storage the caller keeps alive —
## the unsafety lives here, not at every call site. No copy; the view shares the bytes.
str_at := fn(p : ptr(u8), n : usize) -> str {
  sl := Slice(u8)(ptr = p, len = n)
  unchecked bitcast(str, sl)
}

## (A content `hash(str)` for `str`-keyed `HashMap(str, V)` is deferred: defining a
## **second** concrete `hash` overload — alongside a user type's own `hash(K)` —
## takes `hash` into the ≥2-overload *mangled* routing, which currently mis-routes a
## generic container's `hash(K)` call for one of them. A string→value map is already
## available via `std::strmap` (`hash_bytes`-keyed), so the port's symbol tables do
## not need generic `HashMap(str, V)`; closing it is gated on the multi-concrete
## derive-overload routing — a careful, separate overload-resolution task.)

## `str_eq` — **content** equality of two strings (§3.6 / derived `Eq`, Comptime
## §5): equal length and equal bytes. The `==`/`!=` operators over `str` operands
## desugar to this (a *content* compare, not the `{ptr, len}` pointer pair).
## O(min length); short-circuits on the first difference.
pub str_eq := fn(a : str, b : str) -> bool {
  if a.len != b.len {
    return false
  }
  ba := bytes(a)
  bb := bytes(b)
  mut i : usize = 0
  while i < ba.len {
    xa := ba[i]
    xb := bb[i]
    if xa != xb {
      return false
    }
    i += 1
  }
  true
}

## `str_cmp` — **lexicographic** byte ordering of two strings (§3.6 / derived
## `Ord`, Comptime §5): `-1` if `a < b`, `0` if equal, `1` if `a > b`. Compares
## bytes up to the shorter length; on a common prefix the **shorter** string is
## the smaller (a prefix precedes its extension). The `<`/`<=`/`>`/`>=` operators
## over `str` operands desugar to `str_cmp(a, b) ⊕ 0`. O(min length).
pub str_cmp := fn(a : str, b : str) -> i64 {
  ba := bytes(a)
  bb := bytes(b)
  n := if ba.len < bb.len { ba.len } else { bb.len }
  mut i : usize = 0
  while i < n {
    xa := ba[i]
    xb := bb[i]
    if xa < xb {
      return 0 - 1
    }
    if xa > xb {
      return 1
    }
    i += 1
  }
  if ba.len < bb.len {
    return 0 - 1
  }
  if ba.len > bb.len {
    return 1
  }
  0
}

## Byte-level text-search primitives (Stdlib §3.6) for parsing / tokenizing. They
## operate on the underlying bytes (a multi-byte code point is matched by its
## bytes); pair with sub-slicing `s[a..b]` to split.

## `index_of` — the index of the first occurrence of byte `b` in `s`, or `None`.
pub index_of := fn(s : str, b : u8) -> Option(usize) {
  bs := bytes(s)
  mut i : usize = 0
  while i < bs.len {
    if bs[i] == b { return Option(usize).Some(i) }
    i += 1
  }
  Option(usize).None
}

## `rindex_of` — the index of the LAST occurrence of byte `b` in `s`, or `None` (the right-to-left
## dual of `index_of`; for finding a final `/` in a path or a final `.` before an extension).
pub rindex_of := fn(s : str, b : u8) -> Option(usize) {
  bs := bytes(s)
  mut i : usize = s.len
  while i > 0 {
    i -= 1
    if bs[i] == b { return Option(usize).Some(i) }
  }
  Option(usize).None
}

## `parse_uint` — parse `s` as a base-10 unsigned integer, or `None` (Stdlib §3.6):
## `None` for an empty string or any non-digit byte; otherwise the value (wrapping
## on overflow — a range check is additive). The inverse of `push_uint`; the
## primitive for reading a number from CLI input / a config line.
pub parse_uint := fn(s : str) -> Option(u64) {
  bs := bytes(s)
  if bs.len == 0 {
    return Option(u64).None
  }
  mut acc : u64 = 0
  mut i : usize = 0
  while i < bs.len {
    c := bs[i]
    if c < 48 {
      return Option(u64).None
    }
    if c > 57 {
      return Option(u64).None
    }
    d := u64(c - 48)
    acc = unchecked acc * 10 + d
    i += 1
  }
  Option(u64).Some(acc)
}

## `parse_hex` — parse `s` as a base-16 unsigned integer, or `None` (Stdlib §3.6):
## `None` for an empty string or any non-hex byte; the value otherwise (wrapping on
## overflow). The hex counterpart of `parse_uint` — for a lexer's `0x…` literals
## (call on the digits after stripping the `0x` prefix). Upper- or lower-case `a`–`f`.
pub parse_hex := fn(s : str) -> Option(u64) {
  bs := bytes(s)
  if bs.len == 0 {
    return Option(u64).None
  }
  mut acc : u64 = 0
  mut i : usize = 0
  while i < bs.len {
    c := bs[i]
    mut d : u64 = 0
    if c >= 48 and c <= 57 {
      d = u64(c - 48)
    } else if c >= 97 and c <= 102 {
      d = u64(c - 97 + 10)
    } else if c >= 65 and c <= 70 {
      d = u64(c - 65 + 10)
    } else {
      return Option(u64).None
    }
    acc = unchecked acc * 16 + d
    i += 1
  }
  Option(u64).Some(acc)
}

## `parse_int` — parse `s` as a base-10 signed integer, or `None` (Stdlib §3.6):
## an optional leading `-`, then one or more digits. `None` for empty / a bare `-`
## / a non-digit. The signed counterpart of `parse_uint` (the inverse of
## `push_int`); wrapping on overflow (a range check is additive).
pub parse_int := fn(s : str) -> Option(i64) {
  bs := bytes(s)
  if bs.len == 0 {
    return Option(i64).None
  }
  mut neg : bool = false
  mut start : usize = 0
  c0 := bs[0]
  if c0 == 45 {
    neg = true
    start = 1
  }
  if start >= bs.len {
    return Option(i64).None
  }
  mut acc : i64 = 0
  mut i : usize = start
  while i < bs.len {
    c := bs[i]
    if c < 48 {
      return Option(i64).None
    }
    if c > 57 {
      return Option(i64).None
    }
    d := i64(c - 48)
    acc = unchecked acc * 10 + d
    i += 1
  }
  if neg {
    acc = 0 - acc
  }
  Option(i64).Some(acc)
}

## `contains_byte` — whether `s` contains byte `b`.
pub contains_byte := fn(s : str, b : u8) -> bool {
  bs := bytes(s)
  mut i : usize = 0
  while i < bs.len {
    if bs[i] == b { return true }
    i += 1
  }
  false
}

## `count_byte` — the number of occurrences of byte `b` in `s`.
pub count_byte := fn(s : str, b : u8) -> usize {
  bs := bytes(s)
  mut n : usize = 0
  mut i : usize = 0
  while i < bs.len {
    if bs[i] == b { n += 1 }
    i += 1
  }
  n
}

## `common_prefix_len` — the length (in bytes) of the longest common prefix of `a` and `b` (the
## number of leading bytes they share). 0 if the first bytes differ or either is empty.
pub common_prefix_len := fn(a : str, b : str) -> usize {
  ba := bytes(a)
  bb := bytes(b)
  n : usize = if a.len < b.len { a.len } else { b.len }
  mut i : usize = 0
  while i < n {
    if ba[i] != bb[i] { return i }
    i += 1
  }
  n
}

## `find_str` — the index of the first occurrence of substring `needle` in `s`, or
## `None` (Stdlib §3.6). The empty needle matches at `0`; a needle longer than `s`
## is `None`. Naive O(n·m) byte scan — fine for short patterns / one-off lookups (a
## linear-time matcher is additive). Pairs with `s[a..b]` to split on a substring.
pub find_str := fn(s : str, needle : str) -> Option(usize) {
  bs := bytes(s)
  bn := bytes(needle)
  if bn.len == 0 {
    return Option(usize).Some(0)
  }
  if bn.len > bs.len {
    return Option(usize).None
  }
  last : usize = bs.len - bn.len
  mut i : usize = 0
  while i <= last {
    mut j : usize = 0
    mut ok : bool = true
    while j < bn.len {
      k : usize = i + j
      xa := bs[k]
      xb := bn[j]
      if xa != xb {
        ok = false
        j = bn.len
      } else {
        j += 1
      }
    }
    if ok {
      return Option(usize).Some(i)
    }
    i += 1
  }
  Option(usize).None
}

## `rfind_str` — the index of the LAST occurrence of substring `needle` in `s`, or `None` (the
## right-to-left dual of `find_str`). The empty needle matches at `s.len`; a needle longer than `s` is
## `None`. Naive O(n·m) scan from the right.
pub rfind_str := fn(s : str, needle : str) -> Option(usize) {
  bs := bytes(s)
  bn := bytes(needle)
  if bn.len == 0 { return Option(usize).Some(bs.len) }
  if bn.len > bs.len { return Option(usize).None }
  mut i : usize = bs.len - bn.len + 1
  while i > 0 {
    i -= 1
    mut j : usize = 0
    mut ok : bool = true
    while j < bn.len {
      if bs[i + j] != bn[j] { ok = false; j = bn.len } else { j += 1 }
    }
    if ok { return Option(usize).Some(i) }
  }
  Option(usize).None
}

## `contains_str` — whether `needle` occurs anywhere in `s` (the bool form of `find_str`). The empty
## needle is contained in every string.
pub contains_str := fn(s : str, needle : str) -> bool {
  match find_str(s, needle) {
    Option::Some(i) => { true }
    Option::None => { false }
  }
}

## `count_str` — the number of NON-OVERLAPPING occurrences of `needle` in `s`, scanning left to right
## (each match advances past the whole needle). An empty needle counts 0 (avoids a non-terminating scan).
pub count_str := fn(s : str, needle : str) -> usize {
  bs := bytes(s)
  bn := bytes(needle)
  if bn.len == 0 or bn.len > bs.len { return 0 }
  last : usize = bs.len - bn.len
  mut n : usize = 0
  mut i : usize = 0
  while i <= last {
    mut j : usize = 0
    mut ok : bool = true
    while j < bn.len {
      if bs[i + j] != bn[j] { ok = false; j = bn.len } else { j += 1 }
    }
    if ok {
      n += 1
      i += bn.len          ## non-overlapping: skip past the whole match
    } else {
      i += 1
    }
  }
  n
}

## `starts_with` — whether `s` begins with `prefix`, byte-for-byte.
pub starts_with := fn(s : str, prefix : str) -> bool {
  if prefix.len > s.len { return false }
  bs := bytes(s)
  bp := bytes(prefix)
  mut i : usize = 0
  while i < bp.len {
    xa := bs[i]
    xb := bp[i]
    if xa != xb { return false }
    i += 1
  }
  true
}

## `ends_with` — whether `s` ends with `suffix`, byte-for-byte.
pub ends_with := fn(s : str, suffix : str) -> bool {
  if suffix.len > s.len { return false }
  bs := bytes(s)
  bq := bytes(suffix)
  off : usize = s.len - suffix.len
  mut i : usize = 0
  while i < bq.len {
    j : usize = off + i
    xa := bs[j]
    xb := bq[i]
    if xa != xb { return false }
    i += 1
  }
  true
}

## `strip_prefix` — `s` with a leading `prefix` removed if it is present, else `s` UNCHANGED. A `str`
## VIEW (no allocation), for peeling a known lead (`strip_prefix(line, "http://")`). Returns a plain
## `str` (not `Option`) — `Option(str)` truncates its payload today; test presence with `starts_with`.
pub strip_prefix := fn(s : str, prefix : str) -> str {
  if not starts_with(s, prefix) { return s }
  p := unchecked bitcast(ptr(u8), bitcast(usize, s.ptr) + prefix.len)
  str_at(p, s.len - prefix.len)
}

## `strip_suffix` — `s` with a trailing `suffix` removed if it is present, else `s` UNCHANGED. A `str`
## VIEW (keeps the start, so no pointer arithmetic).
pub strip_suffix := fn(s : str, suffix : str) -> str {
  if not ends_with(s, suffix) { return s }
  str_at(s.ptr, s.len - suffix.len)
}

## `trim_start_matches` / `trim_end_matches` / `trim_matches` — like `trim*` but strip a SPECIFIC byte
## `b` (not whitespace) from the start / end / both ends. A `str` VIEW (no allocation) — for peeling
## quotes, brackets, a padding char, etc. (`trim_matches(field, 34)` drops surrounding `"`).
pub trim_start_matches := fn(s : str, b : u8) -> str {
  bs := bytes(s)
  mut i : usize = 0
  while i < s.len and bs[i] == b { i += 1 }
  p := unchecked bitcast(ptr(u8), bitcast(usize, s.ptr) + i)
  str_at(p, s.len - i)
}
pub trim_end_matches := fn(s : str, b : u8) -> str {
  bs := bytes(s)
  mut n : usize = s.len
  while n > 0 and bs[n - 1] == b { n -= 1 }
  str_at(s.ptr, n)
}
pub trim_matches := fn(s : str, b : u8) -> str {
  t := trim_start_matches(s, b)
  trim_end_matches(t, b)
}

## True for an ASCII whitespace byte — space, tab (`\t`), newline (`\n`), carriage return (`\r`).
is_ascii_ws := fn(b : u8) -> bool { b == 32 or b == 9 or b == 10 or b == 13 }

## `s` with leading ASCII whitespace removed — a `str` VIEW over the original bytes (no allocation),
## the same sub-slice shape `split` yields. `trim_start`/`trim_end`/`trim` compose.
pub trim_start := fn(s : str) -> str {
  bs := bytes(s)
  mut i : usize = 0
  while i < s.len and is_ascii_ws(bs[i]) { i += 1 }
  p := unchecked bitcast(ptr(u8), bitcast(usize, s.ptr) + i)
  str_at(p, s.len - i)
}

## `s` with trailing ASCII whitespace removed (keeps the start, so no pointer arithmetic).
pub trim_end := fn(s : str) -> str {
  bs := bytes(s)
  mut n : usize = s.len
  while n > 0 and is_ascii_ws(bs[n - 1]) { n -= 1 }
  str_at(s.ptr, n)
}

## `s` with BOTH leading and trailing ASCII whitespace removed. The intermediate `trim_start` result is
## bound to a local `t` before `trim_end` (a str is a 2-word aggregate; the lean lower does not yet pass
## a nested aggregate-RETURNING call directly as an argument — bind it first, per AGENTS.md).
pub trim := fn(s : str) -> str {
  t := trim_start(s)
  trim_end(t)
}

## Byte-level ASCII classification + case folding (allocation-free, `str`-VIEW-friendly). ASCII only —
## a non-ASCII byte (≥128, a UTF-8 continuation/lead) is returned unchanged, so these are safe to fold
## over UTF-8 bytes without corrupting multi-byte code points.
pub is_ascii_upper := fn(b : u8) -> bool { b >= 65 and b <= 90 }        ## 'A'..'Z'
pub is_ascii_lower := fn(b : u8) -> bool { b >= 97 and b <= 122 }       ## 'a'..'z'
pub is_ascii_digit := fn(b : u8) -> bool { b >= 48 and b <= 57 }        ## '0'..'9'
pub is_ascii_alpha := fn(b : u8) -> bool { is_ascii_upper(b) or is_ascii_lower(b) }

## `b` folded to ASCII lower case ('A'..'Z' → +32); every other byte unchanged.
pub to_ascii_lower := fn(b : u8) -> u8 { if is_ascii_upper(b) { b + 32 } else { b } }
## `b` folded to ASCII upper case ('a'..'z' → -32); every other byte unchanged.
pub to_ascii_upper := fn(b : u8) -> u8 { if is_ascii_lower(b) { b - 32 } else { b } }

## `eq_ignore_ascii_case` — byte-for-byte equality after folding each side to ASCII lower case (a
## case-insensitive compare for ASCII text — `"Fn" ≡ "fn"`). Allocation-free (no new string): both
## operands are compared in place. Non-ASCII bytes must match exactly (fold is a no-op on them).
pub eq_ignore_ascii_case := fn(a : str, b : str) -> bool {
  if a.len != b.len { return false }
  ba := bytes(a)
  bb := bytes(b)
  mut i : usize = 0
  while i < ba.len {
    if to_ascii_lower(ba[i]) != to_ascii_lower(bb[i]) { return false }
    i += 1
  }
  true
}

## `CharIter` — a **code-point** iterator over a `str`'s UTF-8 bytes (§3.6): the
## backing bytes plus the current byte position. Built by `chars(s)`; satisfies the
## **Iterator** protocol (Stdlib §2.4: `iter` returns itself, `next` decodes one
## code point and advances), so `for c in chars(s) { … }` walks the string by
## **code point**, not byte (`for b in bytes(s)` walks bytes). Its `iter`/`next`
## are free-function **overloads** keyed on `CharIter`, so they coexist with
## any other type's `iter`/`next`.
pub CharIter := struct { ptr : ptr(u8), len : usize, pos : usize }

## A code-point iterator over `s`.
chars := fn(s : str) -> CharIter {
  CharIter(ptr = s.ptr, len = s.len, pos = 0)
}

## The byte at index `i` of the iterator's backing memory. `str_at` is an
## explicitly unchecked escape hatch, so retain the view's length by indexing a
## Slice; the compiler then emits its checked bounds guard before the load.
char_byte := fn(c : CharIter, i : usize) -> u8 {
  view := Slice(u8)(ptr = c.ptr, len = c.len)
  view[i]
}

## A `CharIter` **is** the iterator — the Iterator protocol's `iter` (identity).
## Returns a constructor copy (a non-place aggregate) rather than the place `c`.
iter := fn(c : CharIter) -> CharIter {
  CharIter(ptr = c.ptr, len = c.len, pos = c.pos)
}

## Decode the next **code point** (UTF-8) and advance; `None` at the end. The
## codepoint is reassembled from 6-bit groups with the standard lead/continuation
## masks, written as arithmetic (`% 64`, `* 64`, …) — the inverse of `push_char`.
next := fn(in out c : CharIter) -> Option(char) {
  if c.pos >= c.len {
    return Option(char).None
  }
  b0 := char_byte(c, c.pos)
  mut cp : u32 = 0
  mut n : usize = 1
  if b0 < 128 {
    cp = u32(b0)
  } else if b0 < 224 {
    comptime if verify.checked {
      if b0 < 194 { panic("invalid UTF-8 lead byte") }
    }
    b1 := char_byte(c, c.pos + 1)
    comptime if verify.checked {
      if b1 < 128 or b1 >= 192 { panic("invalid UTF-8 continuation byte") }
    }
    hi := u32(b0 % 32) * 64
    cp = hi + u32(b1 % 64)
    n = 2
  } else if b0 < 240 {
    b1 := char_byte(c, c.pos + 1)
    b2 := char_byte(c, c.pos + 2)
    comptime if verify.checked {
      if b1 < 128 or b1 >= 192 { panic("invalid UTF-8 continuation byte") }
      if b2 < 128 or b2 >= 192 { panic("invalid UTF-8 continuation byte") }
      if b0 == 224 and b1 < 160 { panic("overlong UTF-8 sequence") }
      if b0 == 237 and b1 >= 160 { panic("UTF-8 surrogate sequence") }
    }
    t0 := u32(b0 % 16) * 4096
    t1 := u32(b1 % 64) * 64
    cp = t0 + t1 + u32(b2 % 64)
    n = 3
  } else {
    comptime if verify.checked {
      if b0 >= 245 { panic("invalid UTF-8 lead byte") }
    }
    b1 := char_byte(c, c.pos + 1)
    b2 := char_byte(c, c.pos + 2)
    b3 := char_byte(c, c.pos + 3)
    comptime if verify.checked {
      if b1 < 128 or b1 >= 192 { panic("invalid UTF-8 continuation byte") }
      if b2 < 128 or b2 >= 192 { panic("invalid UTF-8 continuation byte") }
      if b3 < 128 or b3 >= 192 { panic("invalid UTF-8 continuation byte") }
      if b0 == 240 and b1 < 144 { panic("overlong UTF-8 sequence") }
      if b0 == 244 and b1 >= 144 { panic("UTF-8 code point out of range") }
    }
    t0 := u32(b0 % 8) * 262144
    t1 := u32(b1 % 64) * 4096
    t2 := u32(b2 % 64) * 64
    cp = t0 + t1 + t2 + u32(b3 % 64)
    n = 4
  }
  c.pos += n
  Option(char).Some(unchecked bitcast(char, cp))
}

## `SplitIter` — splits a `str` into the substrings between occurrences of a
## separator **byte** `sep` (Stdlib §3.6), yielding each piece as a `str` view
## (no copy — a sub-slice into the original). Like `CharIter`, it satisfies the
## **Iterator** protocol (Stdlib §2.4) via free-function `iter`/`next` overloads
## keyed on `SplitIter`, so `for part in split(s, sep) { … }` walks the
## fields. Standard split semantics: `n` separators yield `n+1` pieces, an empty
## piece between adjacent separators, and a trailing separator a final empty
## piece. Splitting on a byte suits the common ASCII delimiters (`,` `=` `\n`
## space); a multi-byte / substring separator is additive.
## Backed by the original's `{ptr, len}` plus the separator and cursor. (A `str`
## *field* read through a borrow is now lowered — `deref(p).field` copies the
## pair — so this flat form is a representation choice, kept for the by-pointer
## parameter convenience below, not a codegen limitation.)
pub SplitIter := struct { ptr : ptr(u8), len : usize, sep : u8, pos : usize, done : bool }

## A splitting iterator over the string at `s` on the separator byte `sep`. Takes
## `s` **by pointer** (`ptr(str)`): a `str`-by-value parameter followed by a
## scalar one goes by-reference on the stack-argument arches (i386 / aarch32), where
## copying it whole / reading its fields is not yet a place — a pointer parameter is
## a scalar and sidesteps that. `deref(s)` materializes the string into a frame
## local whose `{ptr, len}` fields are readable everywhere.
pub split := fn(s : ptr(str), sep : u8) -> SplitIter {
  ss := deref(s)
  SplitIter(ptr = ss.ptr, len = ss.len, sep = sep, pos = 0, done = false)
}

## The byte at index `i` of the iterator's backing memory.
split_byte := fn(it : SplitIter, i : usize) -> u8 {
  base := unchecked bitcast(usize, it.ptr)
  unchecked deref(bitcast(ptr(u8), base + i))
}

## The `str` view over the backing bytes `[a, b)` — a `{ptr, len}` over the range,
## reinterpreted as `str` (the bytes are the original's, valid UTF-8 at separator
## boundaries since the separator is a single ASCII byte).
split_piece := fn(it : SplitIter, a : usize, b : usize) -> str {
  p := unchecked bitcast(ptr(u8), bitcast(usize, it.ptr) + a)
  sl := Slice(u8)(ptr = p, len = b - a)
  unchecked bitcast(str, sl)
}

## A `SplitIter` **is** the iterator — the Iterator protocol's `iter` (identity).
## Returns a constructor copy (a non-place aggregate), not the place `it`.
iter := fn(it : SplitIter) -> SplitIter {
  SplitIter(ptr = it.ptr, len = it.len, sep = it.sep, pos = it.pos, done = it.done)
}

## The next piece (the bytes up to the next separator, or the remainder), then
## advance past the separator; `None` once the last piece has been yielded.
next := fn(in out it : SplitIter) -> Option(str) {
  if it.done {
    return Option(str).None
  }
  start := it.pos
  mut i : usize = it.pos
  while i < it.len {
    if split_byte(it, i) == it.sep {
      piece := split_piece(it, start, i)
      it.pos = i + 1
      return Option(str).Some(piece)
    }
    i += 1
  }
  it.done = true
  last := split_piece(it, start, it.len)
  Option(str).Some(last)
}
