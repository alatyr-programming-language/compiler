## std::serialize — a little-endian binary encoder + decoder for primitive types
## over an arena. The foundation any binary format builds on: fixed-width unsigned
## and signed integers, `bool`, IEEE-754 `f64`, and length-prefixed byte / string
## blobs, all in **little-endian** byte order.
##
## Tier (D91): a **std**-tier convenience over the **alloc**-tier `StrBuf` (the
## growable byte buffer that backs the encoder) and the base-tier `Slice(u8)` /
## `Result` / `Option`. The encoder appends into a caller-provided `StrBuf`; the
## decoder reads back from a borrowed `Slice(u8)` through a bounds-checked cursor,
## so a short read surfaces `SerError.UnexpectedEof` — never a silent garbage read.
##
## Every fallible operation returns a **concrete** `Result(_, SerError)` (never a
## type-parameter payload), so the public surface sidesteps the generic-payload
## Option/Result delivery hazard: callers `match` (or `?`-propagate) the result.

## The only two failures this layer can raise: the decoder running past the end of
## its input, and the encoder's backing arena running out of memory.
pub SerError := enum { UnexpectedEof, OutOfMemory }

## ---------------------------------------------------------------------------
## Encoder — append little-endian bytes into a `StrBuf` (the buffer grows through
## its arena; the sole real failure is OOM, mapped to `SerError.OutOfMemory`).
## ---------------------------------------------------------------------------

## Append one raw byte, mapping the buffer's `AllocError` to `SerError`.
put_byte := fn(in out b : alloc::strbuf::StrBuf, v : u8) -> Result(usize, SerError) {
  match alloc::strbuf::push_byte(b, v) {
    Ok(n) => { return Result(usize, SerError).Ok(n) }
    Err(e) => { return Result(usize, SerError).Err(SerError.OutOfMemory) }
  }
}

## Append the low `nbytes` bytes of `v`, least-significant byte first (little-endian).
put_uint := fn(in out b : alloc::strbuf::StrBuf, v : u64, nbytes : usize) -> Result(usize, SerError) {
  mut k : usize = 0
  while k < nbytes {
    sh := unchecked { v.shr(8 * k) }
    put_byte(b, u8(sh & 255))?
    k = k + 1
  }
  Result(usize, SerError).Ok(nbytes)
}

pub put_u8  := fn(in out b : alloc::strbuf::StrBuf, v : u8)  -> Result(usize, SerError) { put_uint(b, u64(v), 1) }
pub put_u16 := fn(in out b : alloc::strbuf::StrBuf, v : u16) -> Result(usize, SerError) { put_uint(b, u64(v), 2) }
pub put_u32 := fn(in out b : alloc::strbuf::StrBuf, v : u32) -> Result(usize, SerError) { put_uint(b, u64(v), 4) }
pub put_u64 := fn(in out b : alloc::strbuf::StrBuf, v : u64) -> Result(usize, SerError) { put_uint(b, v, 8) }

## Signed integers: reinterpret to the same-width unsigned via `bitcast`, then the
## unsigned little-endian path (two's-complement bit pattern is preserved).
pub put_i8  := fn(in out b : alloc::strbuf::StrBuf, v : i8)  -> Result(usize, SerError) { put_uint(b, u64(bitcast(u8, v)),  1) }
pub put_i16 := fn(in out b : alloc::strbuf::StrBuf, v : i16) -> Result(usize, SerError) { put_uint(b, u64(bitcast(u16, v)), 2) }
pub put_i32 := fn(in out b : alloc::strbuf::StrBuf, v : i32) -> Result(usize, SerError) { put_uint(b, u64(bitcast(u32, v)), 4) }
pub put_i64 := fn(in out b : alloc::strbuf::StrBuf, v : i64) -> Result(usize, SerError) { put_uint(b, bitcast(u64, v),      8) }

## One byte, `1` for `true` / `0` for `false`.
pub put_bool := fn(in out b : alloc::strbuf::StrBuf, v : bool) -> Result(usize, SerError) {
  bv : u8 = if v { 1 } else { 0 }
  put_byte(b, bv)
}

## An `f64` as its IEEE-754 bits (`bitcast(u64, x)`), little-endian.
pub put_f64 := fn(in out b : alloc::strbuf::StrBuf, x : f64) -> Result(usize, SerError) {
  put_u64(b, unchecked bitcast(u64, x))
}

## A byte blob: a `u32` little-endian length prefix, then the raw bytes.
pub put_bytes := fn(in out b : alloc::strbuf::StrBuf, bs : Slice(u8)) -> Result(usize, SerError) {
  put_u32(b, u32(bs.len))?
  mut i : usize = 0
  while i < bs.len {
    put_byte(b, bs[i])?
    i = i + 1
  }
  Result(usize, SerError).Ok(bs.len)
}

## A string: its UTF-8 bytes, length-prefixed (identical wire form to `put_bytes`).
pub put_str := fn(in out b : alloc::strbuf::StrBuf, s : str) -> Result(usize, SerError) {
  put_bytes(b, bytes(s))
}

## ---------------------------------------------------------------------------
## Decoder — a bounds-checked cursor over a borrowed byte range. `pos` advances as
## values are read; a read that would pass the end returns `SerError.UnexpectedEof`.
##
## The range is held as **flat scalar** fields — the start address as a `usize`
## (`base`), the byte length (`len`), and the cursor (`pos`) — rather than a nested
## `Slice(u8)` field: reading a nested aggregate field out of a by-reference struct
## parameter is a codegen hazard, so the cursor keeps everything scalar and forms
## the element pointer by arithmetic.
## ---------------------------------------------------------------------------

pub Reader := struct { base : usize, len : usize, pos : usize }

## A fresh reader positioned at the start of `data` (borrows the slice's bytes).
pub reader := fn(data : Slice(u8)) -> Reader {
  Reader(base = unchecked bitcast(usize, data.ptr), len = data.len, pos = 0)
}

## Bytes not yet consumed.
pub remaining := fn(r : ptr(Reader)) -> usize {
  rr := deref(r)
  rr.len - rr.pos
}

## Read one byte, advancing the cursor; `UnexpectedEof` if none remains.
rd_byte := fn(in out r : Reader) -> Result(u8, SerError) {
  if r.pos >= r.len { return Result(u8, SerError).Err(SerError.UnexpectedEof) }
  p := unchecked bitcast(ptr(u8), r.base + r.pos)
  b := deref(p)
  r.pos = r.pos + 1
  Result(u8, SerError).Ok(b)
}

## Reassemble `nbytes` little-endian bytes into a `u64` (`b0 | b1<<8 | …`).
get_uint := fn(in out r : Reader, nbytes : usize) -> Result(u64, SerError) {
  mut acc : u64 = 0
  mut k : usize = 0
  while k < nbytes {
    b := rd_byte(r)?
    acc = acc | unchecked { u64(b).shl(8 * k) }
    k = k + 1
  }
  Result(u64, SerError).Ok(acc)
}

pub get_u8  := fn(in out r : Reader) -> Result(u8, SerError)  { v := get_uint(r, 1)?; Result(u8, SerError).Ok(u8(v)) }
pub get_u16 := fn(in out r : Reader) -> Result(u16, SerError) { v := get_uint(r, 2)?; Result(u16, SerError).Ok(u16(v)) }
pub get_u32 := fn(in out r : Reader) -> Result(u32, SerError) { v := get_uint(r, 4)?; Result(u32, SerError).Ok(u32(v)) }
pub get_u64 := fn(in out r : Reader) -> Result(u64, SerError) { v := get_uint(r, 8)?; Result(u64, SerError).Ok(v) }

## Sign-extend the low `bits` bits of `v` into a canonical `i64`. A bare
## `bitcast(iN, uN(v))` off freshly-assembled bytes does **not** sign-extend (the
## upper register bits stay zero), so a narrow signed value must be extended
## explicitly before it is narrowed to its `iN` type — otherwise a negative decodes
## as a large positive. `bits` is 8/16/32 here (never 64: `get_i64` needs no extend).
sign_ext := fn(v : u64, bits : usize) -> i64 {
  sign : u64 = unchecked { u64(1).shl(bits - 1) }
  if (v & sign) != 0 {
    top : u64 = unchecked { 18446744073709551615.shl(bits) }
    return bitcast(i64, v | top)
  }
  bitcast(i64, v)
}

pub get_i8  := fn(in out r : Reader) -> Result(i8, SerError)  { v := get_uint(r, 1)?; Result(i8, SerError).Ok(i8(sign_ext(v, 8))) }
pub get_i16 := fn(in out r : Reader) -> Result(i16, SerError) { v := get_uint(r, 2)?; Result(i16, SerError).Ok(i16(sign_ext(v, 16))) }
pub get_i32 := fn(in out r : Reader) -> Result(i32, SerError) { v := get_uint(r, 4)?; Result(i32, SerError).Ok(i32(sign_ext(v, 32))) }
pub get_i64 := fn(in out r : Reader) -> Result(i64, SerError) { v := get_uint(r, 8)?; Result(i64, SerError).Ok(bitcast(i64, v)) }

## One byte → `bool` (any non-zero byte is `true`).
pub get_bool := fn(in out r : Reader) -> Result(bool, SerError) {
  b := rd_byte(r)?
  Result(bool, SerError).Ok(b != 0)
}

## Eight little-endian bytes → `f64` (the inverse of `put_f64`).
pub get_f64 := fn(in out r : Reader) -> Result(f64, SerError) {
  bits := get_uint(r, 8)?
  Result(f64, SerError).Ok(unchecked bitcast(f64, bits))
}

## A length-prefixed byte blob as a **borrowed** `Slice(u8)` view into the input
## (no copy — valid while the underlying buffer lives). A short read (the length
## prefix or the payload running past the end) is a **located trap** (I11), not a
## `Result` — the aggregate view is returned by value, so it cannot ride an `Ok`
## payload (a `Result` with an aggregate payload mis-delivers on this backend). A
## caller that must recover from truncation checks `remaining(r)` first.
pub get_bytes := fn(in out r : Reader) -> Slice(u8) {
  ln := usize(read_len(r))
  if r.pos + ln > r.len { panic("std::serialize: unexpected end of input reading a byte blob") }
  view := Slice(u8)(ptr = unchecked bitcast(ptr(u8), r.base + r.pos), len = ln)
  r.pos = r.pos + ln
  view
}

## The `u32` little-endian length prefix, trapping on a short read (helper for the
## blob readers, whose own return value is the aggregate view, not a `Result`).
read_len := fn(in out r : Reader) -> u32 {
  match get_u32(r) {
    Ok(n) => { return n }
    Err(e) => { panic("std::serialize: unexpected end of input reading a length prefix") }
  }
}

## A length-prefixed string as a borrowed `str` view over the input bytes (same
## wire form as `get_bytes`; the bytes are assumed valid UTF-8). Short read → a
## located trap (as `get_bytes`). The `str` is produced by tail-returning the base
## `str_at(p, n)` view constructor: a `str` returned by *value* from a locally
## `bitcast`-formed pair truncates on this backend, whereas the value returned by a
## cross-module `str`-returning call is delivered intact — so the construction is
## routed through `str_at` (ambient from the base tier).
pub get_str := fn(in out r : Reader) -> str {
  ln := usize(read_len(r))
  if r.pos + ln > r.len { panic("std::serialize: unexpected end of input reading a string") }
  p := unchecked bitcast(ptr(u8), r.base + r.pos)
  r.pos = r.pos + ln
  str_at(p, ln)
}
