## std::strbuf — a growable byte buffer (a UTF-8 string builder) over OS memory.
##
## Allocator-borne (as for std::vec): the backing bytes come from a
## pluggable **`Arena`** (the region protocol), not a direct `mmap`. The buffer
## holds a borrow of that arena (`arena`) so a growing `push_byte` reaches it; reads
## use the cached pointer. (`format` is given the arena; `print`/`println` make a
## throwaway one internally, so their callers are unaffected.)
##
## Tier discipline: this is the **alloc** tier — it manages the in-memory
## buffer only and never reaches the OS. Writing the buffer to stdout is a
## **std-tier** operation (`std::fmt::write_buf`), so no `sys_write` is declared here.

## { backing bytes, byte length, capacity (bytes), the arena it allocates from }.
##
## `@owning`: a `StrBuf` (and thus `String`, its alias) is a linear handle,
## consumed by `strbuf_free` once — `free` only `forget`s; the backing pages belong
## to the arena (reclaimed via `std::os::free`). **Handle-based (Memory §5.3.1 /
##):** it stores the backing's arena **index** (`idx`), NOT a pointer, plus a
## borrow of its arena to resolve it per access (`strbuf_base` → `get`) and to grow.
## Mutations (`push_*`, `write`) borrow `in out`; reads (`print_buf`, `buf_len`) by
## **scoped reference** `in s : ptr(StrBuf)`; `by_value` moves it out.
pub StrBuf := @owning struct { idx : usize, len : usize, cap : usize, arena : ptr(mut Arena) }

## A new buffer with room for `cap` bytes (`cap >= 1`), backed by arena `a` (kept as
## a borrow for per-access resolution + grow). Traps on exhaustion (I11); stores the
## backing's handle index.
pub strbuf := fn(a : ptr(mut Arena), cap : usize) -> StrBuf {
  idx := allocate(deref(a), u8, cap, 1).expect("strbuf: allocator out of memory").idx
  StrBuf(idx = idx, len = 0, cap = cap, arena = a)
}

## The backing's start address, resolved from the stored handle via the stored arena
## (`get(arena, handle)`). The scoped pointer is used immediately by the caller and
## never stored (§5.3.1).
pub strbuf_base := fn(s : ptr(StrBuf)) -> ptr(mut u8) {
  aa := deref(deref(s).arena)
  p := alloc::get(u8, aa, Handle(u8)(idx = deref(s).idx))
  ## `get`'s result is scoped to the arena (§5.4) — returning it is a deliberate
  ## first-class escape (§5.6 rule 5, the trusted allocator layer): fabricate the raw
  ## pointer under `unchecked`. Validity rests on the arena outliving the buffer.
  unchecked bitcast(ptr(mut u8), bitcast(usize, p))
}

## Ensure room for `extra` more bytes, growing the backing through the **arena**
## when needed: allocate a new block (doubling capacity until it fits), copy the
## bytes (byte-by-byte — a whole-aggregate store through a pointer is not lowered),
## and update the stored handle (the old block is left to the arena's bulk reclaim).
## This is the **sole allocating step** — and it is **fallible**: a growth that
## exhausts the allocator surfaces `AllocError`, it does **not** trap. (`AllocError`
## is a base-prelude enum — a `StrBuf`/`String` is an alloc-tier value whose only
## real failure is OOM, so its `Writer` error stays base/alloc-tier, never std-tier
## `IoError`; tier discipline, Stdlib §1.) The arena is reached through the stored borrow.
ensure := fn(in out s : StrBuf, extra : usize) -> Result(usize, AllocError) {
  need := s.len + extra
  if need <= s.cap { return Result(usize, AllocError).Ok(s.cap) }
  mut new_cap : usize = s.cap
  while new_cap < need { new_cap = new_cap * 2 }
  ## The sole allocating step — surfaces `AllocError` on exhaustion, propagated
  ## with `?` and the handle index extracted in one step.
  nidx := allocate(deref(s.arena), u8, new_cap, 1)?.idx
  aa := deref(s.arena)
  oldp := alloc::get(u8, aa, Handle(u8)(idx = s.idx))
  newp := alloc::get(u8, aa, Handle(u8)(idx = nidx))
  old_int := unchecked bitcast(usize, oldp)
  new_int := unchecked bitcast(usize, newp)
  mut k : usize = 0
  while k < s.len {
    sb := unchecked bitcast(ptr(mut u8), old_int + k)
    db := unchecked bitcast(ptr(mut u8), new_int + k)
    deref(db) = deref(sb)
    k += 1
  }
  s.idx = nidx
  s.cap = new_cap
  Result(usize, AllocError).Ok(new_cap)
}

## Ensure room for `additional` more bytes without reallocating (§160): the public
## face of `ensure`. **Fallible** — surfaces `AllocError` on exhaustion, never
## traps. Call before a known batch of `push`es to amortize the growth.
pub reserve := fn(in out s : StrBuf, additional : usize) -> Result(usize, AllocError) {
  ensure(s, additional)
}

## Append one byte, growing through the arena when full (`ensure`). **Fallible**
## (`?`-propagates `AllocError`): the in-memory rendering layer threads the
## allocator's failure up to the `Writer` surface (`write`) and `format`, rather
## than trapping. The trapping conveniences (`std::string`, `print`/`println`)
## absorb it at their boundary.
pub push_byte := fn(in out s : StrBuf, b : u8) -> Result(usize, AllocError) {
  ensure(s, 1)?
  ab := deref(s.arena)
  base := alloc::get(u8, ab, Handle(u8)(idx = s.idx))
  base_int := unchecked bitcast(usize, base)
  elem := unchecked bitcast(ptr(mut u8), base_int + s.len)
  deref(elem) = b
  s.len += 1
  Result(usize, AllocError).Ok(1)
}

## Append a string's raw UTF-8 bytes (via the `[u8]` view, so no code-point
## boundary check — we copy bytes, not code points).
pub push_str := fn(in out s : StrBuf, t : str) -> Result(usize, AllocError) {
  bs := bytes(t)
  mut i : usize = 0
  while i < bs.len {
    push_byte(s, bs[i])?
    i += 1
  }
  Result(usize, AllocError).Ok(bs.len)
}

## Append an unsigned integer's base-10 text to the buffer (most-significant
## digit first; `0` → `"0"`). The render-into-a-buffer counterpart of
## `std::io::print_uint` — formatted output of a computed value, built into a
## `StrBuf` rather than written straight to a stream (Stdlib §2.7 / §4).
pub push_uint := fn(in out s : StrBuf, n : u64) -> Result(usize, AllocError) {
  if n >= 10 {
    push_uint(s, n / 10)?
  }
  push_byte(s, u8(n % 10 + 48))?
  Result(usize, AllocError).Ok(0)
}

## Append a signed integer's base-10 text, with a leading `-` for a negative
## value (the counterpart of `std::io::print_int`).
pub push_int := fn(in out s : StrBuf, n : i64) -> Result(usize, AllocError) {
  if n < 0 {
    push_byte(s, 45)?
    bits := bitcast(u64, n)
    ## Compute the magnitude without evaluating the unrepresentable signed negation;
    ## the subtraction and final increment are both representable for i64::MIN.
    magnitude := 18446744073709551615 - bits + 1
    push_uint(s, magnitude)?
    return Result(usize, AllocError).Ok(0)
  }
  push_uint(s, bitcast(u64, n))?
  Result(usize, AllocError).Ok(0)
}

## Append a `char` as its **UTF-8** bytes (1–4 bytes; the counterpart of a
## `char`'s textual rendering, Stdlib §2.7). The codepoint is split into 6-bit
## groups (`/64`, `%64`) with the standard lead/continuation byte tags.
## A UTF-8 continuation byte for the low 6 bits of `x` (`10xxxxxx`). Bound to a
## local at each call site to keep argument expressions shallow (the scratch
## budget).
cont := fn(x : u32) -> u8 {
  u8(128 + x % 64)
}

pub push_char := fn(in out s : StrBuf, c : char) -> Result(usize, AllocError) {
  cp := u32(c)
  if cp < 128 {
    push_byte(s, u8(cp))?
    return Result(usize, AllocError).Ok(1)
  }
  if cp < 2048 {
    lead := u8(192 + cp / 64)
    push_byte(s, lead)?
    push_byte(s, cont(cp))?
    return Result(usize, AllocError).Ok(2)
  }
  if cp < 65536 {
    lead := u8(224 + cp / 4096)
    mid := cont(cp / 64)
    push_byte(s, lead)?
    push_byte(s, mid)?
    push_byte(s, cont(cp))?
    return Result(usize, AllocError).Ok(3)
  }
  lead := u8(240 + cp / 262144)
  hi := cont(cp / 4096)
  mid := cont(cp / 64)
  push_byte(s, lead)?
  push_byte(s, hi)?
  push_byte(s, mid)?
  push_byte(s, cont(cp))?
  Result(usize, AllocError).Ok(4)
}

## Append a `f64`'s base-10 text — an **interim** decimal rendering (Stdlib §2.7):
## an optional leading `-`, the integer part, `.`, then up to 6 fractional digits
## with trailing zeros trimmed (a whole value renders `x.0`). This is truncating,
## **not** shortest-round-trip; NaN / ∞ / very-large magnitudes are outside this
## minimal layer (a proper Grisu/Ryū formatter is additive). Each step binds its
## operands to locals to stay within the scratch-register budget.
pub push_float := fn(in out s : StrBuf, x : f64) -> Result(usize, AllocError) {
  ## Non-finite values render as words, not a decimal expansion — detected by the
  ## bit pattern (robust regardless of comparison's NaN handling): with the sign
  ## masked off, **±∞** is exactly the all-ones exponent + zero mantissa
  ## (`0x7FF0…0`), and any value **above** that is a **NaN** (all-ones exponent +
  ## non-zero mantissa). The sign is the top bit.
  bits := unchecked bitcast(u64, x)
  absbits := bits & 9223372036854775807
  if absbits > 9218868437227405312 {
    push_str(s, "nan")?
    return Result(usize, AllocError).Ok(0)
  }
  if absbits == 9218868437227405312 {
    if bits != absbits { push_byte(s, 45)? }
    push_str(s, "inf")?
    return Result(usize, AllocError).Ok(0)
  }
  mut v : f64 = x
  if v < 0.0 {
    push_byte(s, 45)?
    v = 0.0 - v
  }
  mut ip := u64(v)
  frac : f64 = v - f64(ip)
  ## Round the fractional part to 6 places (nearest), carrying into the integer
  ## part when it rounds up to a whole — so `0.9999997` prints `1.0`, not `0.…`.
  scaled : f64 = frac * 1000000.0 + 0.5
  mut r := u64(scaled)
  if r >= 1000000 {
    r = r - 1000000
    ip += 1
  }
  push_uint(s, ip)?
  push_byte(s, 46)?
  if r == 0 {
    push_byte(s, 48)?
    return Result(usize, AllocError).Ok(0)
  }
  ## Trim trailing zeros, shrinking the printed field width (so `0.5` is `.5`, not
  ## `.500000`); always keep at least one digit.
  mut digits : u64 = r
  mut width : usize = 6
  mut go : bool = true
  while go {
    if width <= 1 {
      go = false
    } else {
      if digits % 10 == 0 {
        digits = digits / 10
        width = width - 1
      } else {
        go = false
      }
    }
  }
  ## Print `digits` as exactly `width` decimal digits (leading zeros), high to low.
  mut p : u64 = 1
  mut k : usize = 1
  while k < width {
    p = p * 10
    k += 1
  }
  while p > 0 {
    dq : u64 = (digits / p) % 10
    push_byte(s, u8(dq + 48))?
    p = p / 10
  }
  Result(usize, AllocError).Ok(0)
}

## Append a byte slice, returning the count accepted — `StrBuf` as a **`Writer`**
## (Stdlib §2.7). Its error is the **writer's own**, of the writer's tier or below
##: a `StrBuf` is alloc-tier and its only real failure is exhausting its
## allocator, so `write` returns `Result(usize, AllocError)` (base-prelude error) —
## **not** the std-tier `IoError` a `Stdout`/`File` writer uses. (Hard-coding
## `IoError` here would be a tier inversion: an alloc-tier value referencing a
## std-tier type, absent on a freestanding+allocator target.) `write_all` / `format`
## compose generically over the error type; OOM mid-write `?`-propagates as
## `AllocError.OutOfMemory`.
pub write := fn(in out s : StrBuf, bs : Slice(u8)) -> Result(usize, AllocError) {
  mut i : usize = 0
  while i < bs.len {
    push_byte(s, bs[i])?
    i += 1
  }
  Result(usize, AllocError).Ok(bs.len)
}

## A by-value constructor copy of the buffer (same backing pages, len, cap) — an
## in-module constructor (a non-place aggregate, lowerable as a result), so a
## builder like `std::fmt::format` can **return the buffer it built** without
## yielding a whole aggregate *place* (a separate lowering path).
## Move the handle out as the function's value — transfers the backing pages to a
## fresh handle and **consumes** the source (`forget(s)` after the field reads).
## Lets `std::fmt::format` return the buffer it built (move-out).
pub by_value := fn(s : StrBuf) -> StrBuf {
  r := StrBuf(idx = s.idx, len = s.len, cap = s.cap, arena = s.arena)
  forget(s)
  r
}

## (Writing the buffer to stdout is a **std-tier** operation — the alloc tier must
## not reach the OS tier discipline. It lives in `std::fmt::write_buf`, which
## reads these bytes via `strbuf_base`/`buf_len` and does the syscall itself.)

## The byte length — a non-consuming scoped-reference read.
pub buf_len := fn(s : ptr(StrBuf)) -> usize {
  deref(s).len
}

## **Consume** the owning handle: the backing pages belong to the **arena**, not
## the buffer, so this no longer `munmap`s — it only `forget(s)`s, discharging the
## obligation. The pages are reclaimed when the caller frees the arena
## (`std::os::free`), one shot.
pub strbuf_free := fn(s : StrBuf) -> isize {
  forget(s)
  0
}
