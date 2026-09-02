## std::string — the owned, growable UTF-8 **`String`** (Stdlib §2.7 / §4).
##
## Honest-staging note (same as std::strbuf / std::vec): the spec's alloc-tier
## `String` is `u8` storage on the **allocator protocol** with **linearity**;
## this is the concrete builder over the std::os `mmap` region, surfaced under
## the canonical name `String`. It folds onto the allocator protocol + linearity
## once those land (the buffer already owns its pages — free it with `free`).
##
## `String` is the owned counterpart of the borrowed `str`: build it with
## `std::fmt::format("{}", …)` (or `string(cap)` + `push_str`/`push`), read its
## length/bytes, write it out, and `free` it.

## The owned string IS the growable byte buffer (std::strbuf). Aliasing keeps a
## single representation: a `String` and a `StrBuf` are the same value, so
## `std::fmt`'s builders (`format`, `display` into a buffer) produce a `String`.
pub String := strbuf::StrBuf

## A new empty string with room for `cap` bytes (`cap >= 1`), backed by arena `a`.
pub string := fn(a : ptr(mut Arena), cap : usize) -> String {
  strbuf::strbuf(a, cap)
}

## `with_capacity` — canonical v1 constructor name (Stdlib §160), alias of `string`.
pub with_capacity := fn(a : ptr(mut Arena), cap : usize) -> String {
  string(a, cap)
}

## `new` — the **basic** constructor: an empty string backed by arena `a`, with a small
## default capacity (it grows on `push`/`push_str`). The stutter-free everyday name
## (Stdlib §160); reach for `with_capacity` when the final size is known.
pub new := fn(a : ptr(mut Arena)) -> String {
  string(a, 16)
}

## A new owned `String` copying the bytes of the borrowed `str` `t` (Stdlib §3.6),
## backed by arena `a`. The owning counterpart of borrowing — keep an input slice
## alive past its source (a parsed token, a map key).
## The growth **mutators** `push`/`push_str` are **fallible** — `Result(usize, AllocError)`
## (§6/§160; String's growth operations surface `AllocError`, never trap on a
## recoverable allocation failure, I11/I3) — and simply propagate `std::strbuf`'s result.
## The **constructors** `string`/`with_capacity`/`from_str` keep their value shape and trap on
## OOM (the spec marks only the mutators fallible); the recoverable construction path is
## `std::fmt::format`, which returns `Result(String, AllocError)`.
pub from_str := fn(a : ptr(mut Arena), t : str) -> String {
  cap : usize = if t.len > 0 { t.len } else { 1 }
  mut s := strbuf::strbuf(a, cap)
  strbuf::push_str(s, t).expect("String::from_str: out of memory")
  strbuf::by_value(s)
}

## Append a string's UTF-8 bytes, returning the **new byte length** or `AllocError`
## (Stdlib appendix §6: "a fallible mutator with no natural result carries a `usize`
## count in its `Ok` arm — the new length for `push`/`push_str`"). `strbuf`'s own
## `push_str` reports the number of bytes it appended, which is the buffer writer's
## convention and not `String`'s, so the count is re-read from the buffer here.
pub push_str := fn(in out s : String, t : str) -> Result(usize, AllocError) {
  strbuf::push_str(s, t)?
  Result(usize, AllocError).Ok(s.len)
}

## Append one `char` as its UTF-8 bytes, returning the **new byte length** or
## `AllocError` (Stdlib appendix §6, as for `push_str`). `strbuf::push_char` reports
## the UTF-8 encoding width it wrote, so the new length is re-read from the buffer.
pub push := fn(in out s : String, c : char) -> Result(usize, AllocError) {
  strbuf::push_char(s, c)?
  Result(usize, AllocError).Ok(s.len)
}

## The byte length — a non-consuming scoped-reference read (`s.len()` via auto-ref;
## `String` is `@owning`).
pub len := fn(s : ptr(String)) -> usize {
  strbuf::buf_len(s)
}

## True when the string is empty (§160) — a non-consuming scoped-reference read.
pub is_empty := fn(s : ptr(String)) -> bool {
  strbuf::buf_len(s) == 0
}

## Remove all bytes (length → 0); the backing capacity is retained (§160). An
## `in out` place borrow (mutation), maintaining the trivially-valid empty UTF-8.
pub clear := fn(in out s : String) {
  s.len = 0
}

## The bytes as a borrowed `[u8]` view (no copy) — for content comparison or
## passing to a byte sink. A non-consuming scoped-reference read; the view aliases
## the storage, so `s` is untouched and the caller still owns and frees it.
pub as_bytes := fn(s : ptr(String)) -> Slice(u8) {
  p := unchecked bitcast(ptr(u8), bitcast(usize, strbuf::strbuf_base(s)))
  Slice(u8)(ptr = p, len = deref(s).len)
}

## The contents as a borrowed `str` view (no copy, Stdlib §3.6) — the owned-string→
## borrowed-`str` bridge (`str` is a `{ptr,len}` over `u8`, the same shape as the
## `Slice(u8)` `as_bytes` yields, so a `bitcast` reinterprets without copying). The
## view aliases the storage and stays valid only while `s` is unmodified (a `push`
## may move the region); a non-consuming scoped-reference read — the caller keeps
## ownership and still frees `s`.
pub as_str := fn(s : ptr(String)) -> str {
  ## Construct the `str` view from the slice's ptr+len via `str_at` (base) rather than
  ## `bitcast(str, <Slice(u8)>)`: an aggregate→aggregate `bitcast` currently copies only word 0
  ## (the ptr) and ZEROES word 1 (the len), so the view came back empty. `bytes()` (the inverse,
  ## base/str) likewise CONSTRUCTS its `Slice` field-by-field rather than bitcasting.
  b := as_bytes(s)
  str_at(b.ptr, b.len)
}

## `reserve` — ensure room for `additional` more bytes without reallocating (§160);
## forwards to the buffer's growth. Fallible (`AllocError`).
pub reserve := fn(in out s : String, additional : usize) -> Result(usize, AllocError) {
  strbuf::reserve(s, additional)
}

## Content equality: equal length and equal bytes (the owned-string counterpart
## of base `str_eq`). Both operands are scoped-reference reads — `a.eq(ptr(b))`
## (auto-ref takes the receiver's address; the second is given explicitly).
pub eq := fn(a : ptr(String), b : ptr(String)) -> bool {
  ba := as_bytes(a)
  bb := as_bytes(b)
  bytes_eq(ba, bb)
}

## (Writing a string to stdout is a **std-tier** operation: use
## `std::fmt::write_buf(s)` — a `String` is a `StrBuf`, so it reads the same way.
## The alloc tier no longer carries a stdout `print`.)

## `to_ascii_lowercase` — a NEW owned `String` with every ASCII 'A'..'Z' byte folded to lower case
## (§3.6; non-ASCII bytes copied unchanged, so UTF-8 is preserved). Allocating: the caller frees it.
pub to_ascii_lowercase := fn(a : ptr(mut Arena), t : str) -> String {
  cap : usize = if t.len > 0 { t.len } else { 1 }
  mut out := strbuf::strbuf(a, cap)
  bt := bytes(t)
  mut i : usize = 0
  while i < t.len {
    b := bt[i]
    lo := if b >= 65 and b <= 90 { b + 32 } else { b }
    strbuf::push_byte(out, lo).expect("to_ascii_lowercase: out of memory")
    i += 1
  }
  strbuf::by_value(out)
}

## `to_ascii_uppercase` — the upper-case counterpart ('a'..'z' → -32; other bytes unchanged).
pub to_ascii_uppercase := fn(a : ptr(mut Arena), t : str) -> String {
  cap : usize = if t.len > 0 { t.len } else { 1 }
  mut out := strbuf::strbuf(a, cap)
  bt := bytes(t)
  mut i : usize = 0
  while i < t.len {
    b := bt[i]
    up := if b >= 97 and b <= 122 { b - 32 } else { b }
    strbuf::push_byte(out, up).expect("to_ascii_uppercase: out of memory")
    i += 1
  }
  strbuf::by_value(out)
}

## `replace` — a NEW owned `String` that is `s` with every non-overlapping occurrence of `from`
## replaced by `to` (left to right). An empty `from` matches nothing (returns a copy of `s`) — a
## deliberate no-op that avoids an infinite loop. Allocating: the caller frees it.
pub replace := fn(a : ptr(mut Arena), s : str, from : str, to : str) -> String {
  cap : usize = if s.len > 0 { s.len } else { 1 }
  mut out := strbuf::strbuf(a, cap)
  bs := bytes(s)
  bf := bytes(from)
  n : usize = s.len
  m : usize = from.len
  mut i : usize = 0
  while i < n {
    mut matched : bool = m > 0 and i + m <= n
    mut j : usize = 0
    while matched and j < m {
      if bs[i + j] != bf[j] { matched = false }
      j += 1
    }
    if matched {
      strbuf::push_str(out, to).expect("replace: out of memory")
      i += m
    } else {
      strbuf::push_byte(out, bs[i]).expect("replace: out of memory")
      i += 1
    }
  }
  strbuf::by_value(out)
}

## `join` — a NEW owned `String` of the `parts` concatenated with `sep` between adjacent elements
## (`join(["a","b","c"], ", ")` → `"a, b, c"`). Empty `parts` → an empty string. Allocating. `parts` is
## a `Slice(str)` — build it over an arena (e.g. `std::os::args`); slicing a `[str; N]` LOCAL is a
## separate open codegen gap. Uses `parts.len()` (the METHOD): `.len` (field) on a slice PARAM is a
## pre-existing miscompile that reads garbage.
pub join := fn(a : ptr(mut Arena), parts : Slice(str), sep : str) -> String {
  mut out := strbuf::strbuf(a, 16)
  mut i : usize = 0
  while i < parts.len() {
    if i > 0 { strbuf::push_str(out, sep).expect("join: out of memory") }
    part := parts[i]
    strbuf::push_str(out, part).expect("join: out of memory")
    i += 1
  }
  strbuf::by_value(out)
}

## `repeat` — a NEW owned `String` of `s` concatenated `n` times (`repeat("ab", 3)` → `"ababab"`).
## `n == 0` → an empty string. Allocating; the caller frees it.
pub repeat := fn(a : ptr(mut Arena), s : str, n : usize) -> String {
  cap : usize = if s.len * n > 0 { s.len * n } else { 1 }
  mut out := strbuf::strbuf(a, cap)
  mut i : usize = 0
  while i < n {
    strbuf::push_str(out, s).expect("repeat: out of memory")
    i += 1
  }
  strbuf::by_value(out)
}

## Release the backing pages (`munmap`) and **consume** the string —
## `strbuf_free` consumes the handle.
pub free := fn(s : String) -> isize {
  strbuf::strbuf_free(s)
}
