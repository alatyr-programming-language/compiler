## std::os — OS-backed memory (Stdlib §7).
##
## An anonymous `mmap` region is a **genuinely owning, releasable** resource — its
## `free` is `munmap`, a real release, unlike the `arena_over` arena over a caller
## buffer (which owns nothing). So it is a **distinct `@owning` type** `OsArena`
## (Memory §5.9) — NOT the same `Arena` — and the linearity checker enforces
## that each `OsArena` is consumed (freed) exactly once on every normal exit. It is
## the linear resource the `alloc` tier (`Vec`/`String`/…) will build on.
##
## `mmap(2)` / `munmap(2)` via `@abi(syscall)` (Linux x86_64: mmap = 9,
## munmap = 11). Raw-level, so wrapped in `unchecked`.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
sys_munmap := @abi(syscall) fn(num : usize, addr : usize, len : usize) -> isize

## `OsArena` — an owning handle to an anonymous `mmap` region: its `base` pointer
## and byte `cap`. `@owning` makes it non-copyable and linear: it must be
## released by `free` (which consumes it) exactly once. It holds an `Arena` over
## the pages for bump allocation via `region` (a borrow).
OsArena := @owning struct { base : ptr(mut bits8), cap : usize }

## Map `len` bytes of fresh, zero-filled, read/write anonymous memory as an owning
## arena. `prot = PROT_READ|PROT_WRITE = 3`; `flags = MAP_PRIVATE|MAP_ANONYMOUS =
## 0x22 = 34`; `fd = -1`; `offset = 0`. This is a fallible std-tier operation:
## `len = 0` is `Err(IoError.InvalidInput)`, and every negative Linux syscall result
## is mapped through `io_error_result` before any pointer is constructed. An `Ok`
## result is the only path that can publish an owning `OsArena`.
pub arena := fn(len : usize) -> Result(OsArena, io::IoError) {
  if len == 0 {
    return Result(OsArena, io::IoError).Err(io::IoError.InvalidInput)
  }
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, len, 3, 34, bitcast(usize, neg1), 0)
  if r < 0 {
    e := i32(0 - r)
    return io::io_error_result(OsArena, e)
  }
  base := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  return Result(OsArena, io::IoError).Ok(OsArena(base = base, cap = len))
}

## A **bump `Arena`** over the arena's pages, for allocation through the region
## mechanism (`allocate(…)` / `get`, Stdlib §5.1). The returned `Arena` is
## **non-owning** — it just views the memory — so the caller keeps the `OsArena`
## (a borrow: reading fields does not consume) and must still `free` it. Reads the
## owning handle's `base`/`cap` **through the borrow pointer** (`deref(a).f`), so
## `osar.region()` yields the allocator without surfacing the raw fields at the
## call site. (Memory §5.2: a `region` allocator hands out `Handle(T)`s into
## these pages; `get(arena, handle)` exchanges a handle for a scoped reference.)
pub region := fn(a : ptr(OsArena)) -> Arena {
  return arena_over(deref(a).base, deref(a).cap)
}

## Release the arena's pages (`munmap`) and **consume** the owning handle: this is
## the linear release. Reads `a`'s fields (borrows), performs the syscall,
## then `forget(a)` discharges the obligation — the pages are gone, the handle is
## defunct, and there is nothing more to consume.
pub free := fn(a : OsArena) -> isize {
  addr := unchecked bitcast(usize, a.base)
  r := unchecked sys_munmap(11, addr, a.cap)
  forget(a)
  return r
}

## --- Process inputs: command-line arguments and environment (Stdlib §7) ------
## Read at **call time** from the OS, not captured at the program entry — so the
## user-written `_start` is untouched and nothing is emitted unless these are
## reached (Stdlib §2). On Linux the source is the per-process `/proc` files;
## both are NUL-separated lists of byte strings, split with `seg_count` / `nth`.

## Read the process's command-line into `buf` (up to `cap` bytes): the program
## name then each argument, **NUL-separated** (Linux `/proc/self/cmdline`).
## Returns the byte count read (`0` if the source could not be opened/read).
## Reuses the `std::io` file surface (which NUL-terminates the path internally).
cmdline_path := fn() -> str { return "/proc/self/cmdline" }

pub read_cmdline := fn(buf : ptr(mut u8), cap : usize) -> usize {
  path := cmdline_path()
  of := io::open(path, 0)
  mut got : usize = 0
  match of {
    Result::Ok(f) => {
      r := io::file_read(f, buf, cap)
      match r {
        Result::Ok(n) => { got = n }
        Result::Err(e) => { got = 0 }
      }
      cc := io::file_close(f)
    }
    Result::Err(e) => { got = 0 }
  }
  return got
}

## Read the process's environment into `buf` (up to `cap` bytes): each entry
## `NAME=VALUE`, **NUL-separated** (Linux `/proc/self/environ`). Returns the
## byte count read.
pub read_environ := fn(buf : ptr(mut u8), cap : usize) -> usize {
  path : str = "/proc/self/environ"
  of := io::open(path, 0)
  mut got : usize = 0
  match of {
    Result::Ok(f) => {
      r := io::file_read(f, buf, cap)
      match r {
        Result::Ok(n) => { got = n }
        Result::Err(e) => { got = 0 }
      }
      cc := io::file_close(f)
    }
    Result::Err(e) => { got = 0 }
  }
  return got
}

## Load the byte at `base + i` (a raw read; callers stay within `[0, len)`).
seg_byte := fn(base : ptr(u8), i : usize) -> u8 {
  e := unchecked bitcast(ptr(u8), bitcast(usize, base) + i)
  return deref(e)
}

## The number of NUL-separated segments in the first `len` bytes at `base` — the
## argument count for a `cmdline` buffer, the entry count for an `environ` one.
pub seg_count := fn(base : ptr(u8), len : usize) -> usize {
  mut c : usize = 0
  mut i : usize = 0
  while i < len {
    b := seg_byte(base, i)
    if b == 0 {
      c += 1
    }
    i += 1
  }
  return c
}

## The `idx`-th NUL-separated segment of the first `len` bytes at `base`, as a
## `[u8]` slice into the buffer (no copy). An out-of-range index yields an empty
## slice. (A `str` view awaits a checked bytes→`str` construction; the bytes are
## valid UTF-8 as the OS delivered them.)
pub nth := fn(base : ptr(u8), len : usize, idx : usize) -> Slice(u8) {
  mut seg : usize = 0
  mut start : usize = 0
  mut i : usize = 0
  while i < len {
    b := seg_byte(base, i)
    if b == 0 {
      if seg == idx {
        p := unchecked bitcast(ptr(u8), bitcast(usize, base) + start)
        return Slice(u8)(ptr = p, len = i - start)
      }
      seg += 1
      start = i + 1
    }
    i += 1
  }
  empty := unchecked bitcast(ptr(u8), bitcast(usize, base) + start)
  return Slice(u8)(ptr = empty, len = 0)
}

## The index of the first `=` byte in `s`, or `s.len` if there is none — the
## key/value split point of a `NAME=VALUE` environment entry.
eq_pos := fn(s : Slice(u8)) -> usize {
  mut i : usize = 0
  while i < s.len {
    if s[i] == 61 {
      return i
    }
    i += 1
  }
  return s.len
}

## Look up an environment variable **by name** within an `environ` buffer (the
## first `len` bytes at `base`, as filled by `read_environ`). Scans each
## NUL-separated `NAME=VALUE` entry; on the first whose key (the bytes before the
## `=`) equals `name`, returns its **value** bytes as a `[u8]` slice into the
## buffer (`Some`); `None` if no entry matches. A read-side, non-allocating named
## lookup — the counterpart of `nth` keyed by name rather than index (Stdlib §7).
## (The allocating `env(name) -> Option(str)` form awaits persistent allocation.)
pub env_lookup := fn(base : ptr(u8), len : usize, name : str) -> Option(Slice(u8)) {
  nb := bytes(name)
  n := seg_count(base, len)
  mut idx : usize = 0
  while idx < n {
    seg := nth(base, len, idx)
    ep := eq_pos(seg)
    if ep < seg.len {
      key := seg[0..ep]
      if bytes_eq(key, nb) {
        vstart := ep + 1
        val := seg[vstart..seg.len]
        return Option(Slice(u8)).Some(val)
      }
    }
    idx += 1
  }
  return Option(Slice(u8)).None
}

## --- Allocating process inputs (Stdlib §7) -----------------------------
## The OS delivers the environment / command line as a transient byte image; the
## allocating forms below copy it into a caller-provided **allocator** and return
## `str`/`[str]` **views into that arena** (region-backed — valid for the
## arena's extent, freed when the caller frees it). Allocator-explicit: no
## implicit or process-static storage. The byte→`str` reinterpret is `unchecked`
## (the OS image is trusted UTF-8; a checked, validating construction is additive).

## `env(allocator, name) -> Option(str)` (Stdlib §7): the value of environment
## variable `name`, or `None`. Copies `/proc/self/environ` into the arena, scans
## for the matching `NAME=VALUE` entry (`env_lookup`), and returns its value bytes
## as a `str` view into the arena.
pub env := fn(a : ptr(mut Arena), name : str) -> Option(str) {
  cap : usize = 32768
  ra := allocate(deref(a), u8, cap, 1)
  mut bidx : usize = 0
  mut ok : bool = false
  match ra {
    Result::Ok(h) => { bidx = h.idx; ok = true }
    Result::Err(e) => { ok = false }
  }
  if not ok { return Option(str).None }
  aa := deref(a)
  base := get(u8, aa, Handle(u8)(idx = bidx))
  bp := unchecked bitcast(ptr(mut u8), bitcast(usize, base))
  n := read_environ(bp, cap)
  rbase := unchecked bitcast(ptr(u8), bitcast(usize, bp))
  r := env_lookup(rbase, n, name)
  match r {
    Some(val) => {
      vv := val
      sv := unchecked bitcast(str, vv)
      return Option(str).Some(sv)
    }
    None => {
      return Option(str).None
    }
  }
}

## `args(allocator) -> [str]` (Stdlib §7): the command-line arguments — the program
## name first, then each argument — as a `Slice(str)`. Copies `/proc/self/cmdline`
## into the arena, then builds a `str` **table** in the arena (one `{ptr, len}` per
## NUL-separated segment, each viewing into the copied bytes) and returns a slice
## over it. The strings and the table are region-backed: valid for the arena's
## extent, freed when the caller frees it (allocator-explicit). Traps on
## allocator exhaustion (the trapping convenience; the recoverable form is additive).
pub args := fn(a : ptr(mut Arena)) -> Slice(str) {
  ## Keep the initial allocation small, but retain and grow the copied image until
  ## the open file reports EOF. `read_cmdline` remains the explicit up-to-cap
  ## low-level helper; the allocating API owns the completeness guarantee.
  mut data := alloc::strbuf::strbuf(a, 65536)
  path := cmdline_path()
  of := io::open(path, 0)
  match of {
    Result::Ok(f) => {
      mut done : bool = false
      while not done {
        chunk : usize = 8192
        alloc::strbuf::reserve(data, chunk).expect("args: allocator out of memory")
        base := unchecked bitcast(usize, alloc::strbuf::strbuf_base(data))
        dst := unchecked bitcast(ptr(mut u8), base + data.len)
        r := io::file_read(f, dst, chunk)
        match r {
          Result::Ok(nr) => {
            if nr == 0 {
              done = true
            } else {
              data.len = data.len + nr
            }
          }
          Result::Err(e) => {
            cc := io::file_close(f)
            alloc::strbuf::strbuf_free(data)
            assert(false)
          }
        }
      }
      cc := io::file_close(f)
    }
    Result::Err(e) => {
      alloc::strbuf::strbuf_free(data)
      assert(false)
    }
  }
  rbase := unchecked bitcast(ptr(u8), bitcast(usize, alloc::strbuf::strbuf_base(data)))
  n := data.len
  alloc::strbuf::strbuf_free(data)
  count := seg_count(rbase, n)
  ## A `str` is two machine words (`{ptr, len}`) — the table stride. (x86_64 /
  ## 64-bit; an arch-general stride is additive, arch-priority §arch.)
  stride : usize = 16
  tb := allocate(deref(a), u8, count * stride, 8)
  mut tidx : usize = 0
  match tb {
    Result::Ok(h) => { tidx = h.idx }
    Result::Err(e) => { panic("args: allocator out of memory") }
  }
  ta := deref(a)
  tbase := get(u8, ta, Handle(u8)(idx = tidx))
  tbase_int := unchecked bitcast(usize, tbase)
  mut i : usize = 0
  while i < count {
    seg := nth(rbase, n, i)
    slot := tbase_int + i * stride
    ## Lay the `{ptr, len}` pair as two word stores (a whole-`str` store through a
    ## pointer is not lowered): the segment's start pointer, then its byte length.
    pf := unchecked bitcast(ptr(mut usize), slot)
    lf := unchecked bitcast(ptr(mut usize), slot + 8)
    deref(pf) = unchecked bitcast(usize, seg.ptr)
    deref(lf) = seg.len
    i += 1
  }
  tp := unchecked bitcast(ptr(str), tbase_int)
  return Slice(str)(ptr = tp, len = count)
}
