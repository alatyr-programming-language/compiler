## selfhost::rt — the lean self-host runtime (a), path-B shape.
## Monomorphic, handle-based: everything is arena-allocated and referenced by a usize
## handle, so the containers are plain (non-generic) structs of word-sized elements — no
## generic-type-declaration form (which diverges between Stage-0 and the self-host parser),
## no multi-word element stores. The self-host lower emits all of this as word ops today.
pub sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## ADDRESSING primitive (I11 / CG-8): compute `base + off` as a POINTER offset, not a checked integer
## `+`. Address arithmetic has ISA-defined (modular) behavior — a REBASED handle (`off = target - base`,
## used for comptime-synthesized names) legitimately wraps `base + off` back to `target`, which the
## integer overflow guard must NOT trap. `unchecked` expresses exactly that (the unchecked/assembly
## level of I11). This is the migration seam: when opaque `usize` handles become typed `ptr(T)`, this
## helper's body becomes native pointer arithmetic and the callers stay unchanged.
pub addr := fn(base : ptr(u8), off : usize) -> ptr(u8) { unchecked { base + off } }

## POINTER DIFFERENCE (I11 / CG-8): the dual of `addr` — `ptr - base` as address arithmetic, not a
## checked integer `-`. Used to REBASE a pointer into a `src`-relative handle (`off = target - src`);
## when `target < src` this deliberately underflows to a huge two's-complement offset that `addr(src,
## off)` later wraps back — the modular round-trip. `unchecked` so the `-` underflow guard never traps
## it. The migration seam's subtraction half (becomes typed pointer difference under usize->ptr).
pub off := fn(p : ptr(u8), base : ptr(u8)) -> usize { unchecked { p - base } }

pub Arena := struct { base : ptr(mut u8), off : usize, cap : usize }

## Map a fresh region and fill `a` as a bump arena (an in-out constructor — Arena is 3 words).
pub arena_init := fn(in out a : Arena, size : usize) {
  fdm1 := 0 - 1
  r := sys_mmap(9, 0, size, 3, 34, fdm1, 0)
  a.base = unchecked bitcast(ptr(mut u8), r)
  a.off = 0
  a.cap = size
}

## Bump `n` bytes, returning the block's start address.
pub bump := fn(in out a : Arena, n : usize) -> usize {
  ## FAIL-LOUD on overflow (I11): a bump past `cap` used to silently overrun the arena's mmap region into
  ## adjacent memory, splicing unrelated bytes into whatever was being built (the Priority-0 self-host GAS
  ## corruption — a manifest buffer bled into the emitted `.s`). `allocate` already bounds-checks; `bump` is
  ## its unchecked twin. Now a capacity breach TRAPS with a clear message instead of corrupting. The build
  ## arenas carry ample headroom (512 MiB), so this never fires on a valid build — it is a safety net.
  if a.off + n > a.cap { panic("rt: arena overflow (bump past cap)") }
  ## `a.base` is now a typed `ptr(mut u8)` (usize->ptr Phase 2): `base + off` is stride-1 pointer
  ## arithmetic (unchecked BY TYPE — an address computation must never overflow-trap), then the block
  ## start is returned as a `usize` address (the arena's word/byte handle currency, unchanged).
  p := unchecked bitcast(usize, a.base + a.off)
  a.off = a.off + n
  return p
}

## A vector of usize handles/words: `data` is the arena address of the element block.
pub Vec := struct { data : ptr(mut u8), len : usize, cap : usize }

pub vec_len := fn(v : Vec) -> usize { return v.len }

## Append a usize element at the next slot; returns the new length (no growth — reserve cap).
pub vec_push := fn(in out v : Vec, x : usize) -> usize {
  ## A Vec is deliberately fixed-capacity: every caller reserves its element block before the first push.
  ## Turn an exhausted reservation into a defined failure before the unchecked address calculation can
  ## overwrite the next arena allocation (I11 / Stdlib §4.1), rather than letting a later read report a
  ## misleading failure or silently continue with corrupted state.
  if v.len >= v.cap { panic("rt: Vec overflow") }
  top := v.data + v.len * 8
  p : ptr(mut usize) = unchecked bitcast(ptr(mut usize), top)
  deref(p) = x
  v.len = v.len + 1
  return v.len
}

## Read element `i` (a usize word).
pub vec_get := fn(v : Vec, i : usize) -> usize {
  p : ptr(usize) = unchecked bitcast(ptr(usize), v.data + i * 8)
  return deref(p)
}

## Record accessors (path B): a multi-word record (e.g. a 3-word Token) is `bump`ed into the
## arena and addressed by its base; its fields are plain words written/read by index. This is
## how the passes store/read aggregates without a generic `Vec(T)` or typed `get(T, …)`: the
## record lives in the arena, a `usize` handle (its base address) goes into a `Vec`, and the
## fields are word-addressed here. All word ops — exactly what the self-host lower emits.

## Write word `i` of the record based at `addr` (a typed `ptr(mut u8)` — `addr + i*8` is stride-1
## pointer arithmetic, unchecked BY TYPE; the base handle is still a usize address at the call sites).
pub rec_set := fn(addr : ptr(mut u8), i : usize, x : usize) {
  p : ptr(mut usize) = unchecked bitcast(ptr(mut usize), addr + i * 8)
  deref(p) = x
}

## Read word `i` of the record based at `addr`.
pub rec_get := fn(addr : ptr(mut u8), i : usize) -> usize {
  p : ptr(usize) = unchecked bitcast(ptr(usize), addr + i * 8)
  return deref(p)
}

## A `str`-element vector (path B): a `str` is two words {ptr, len}, so each element is a 2-word
## record `bump`ed into the arena, its base handle pushed into a `Vec`. This is the lean stand-in
## for `alloc::vec(str)` at the driver's I/O boundary (the file-path / module-source lists) — no
## generic `Vec(T)`/`get(T,…)`, all word ops the self-host lower emits. `push` stores {ptr, len};
## `get` reconstructs the `str` via `str_at` (a Stage-0 builtin AND a self-host-inlined view).
pub svec_str_push := fn(in out v : Vec, in out a : Arena, s : str) -> usize {
  h := bump(a, 16)
  rec_set(h, 0, unchecked bitcast(usize, s.ptr))
  rec_set(h, 1, s.len)
  return vec_push(v, h)
}
pub svec_str_get := fn(v : Vec, i : usize) -> str {
  h := vec_get(v, i)
  return str_at(rec_get(h, 0), rec_get(h, 1))
}

## The `write` syscall (num 1): write `n` bytes at `buf` to file descriptor `fd`. The lean
## runtime's one output primitive — the emitter flushes its assembled GAS through it.
pub sys_write := @abi(syscall) fn(num : usize, fd : usize, buf : usize, n : usize) -> isize

## File-INPUT syscalls — the source-read primitives the self-hosted driver needs to pull `.al`
## files off disk (the read counterpart of `sys_write`). Raw Linux x86_64 numbers, no libc, no
## `std::io`/`Result` wrapper: the driver checks the raw `isize` return (< 0 = error). `sys_open`
## (num 2): open(path, flags, mode) — `path` is a NUL-terminated C-string address, returns the fd
## (or < 0). `sys_read` (num 0): read(fd, buf, n) — returns bytes read (0 = EOF, < 0 = error).
## `sys_close` (num 3): close(fd).
pub sys_open := @abi(syscall) fn(num : usize, path : usize, flags : usize, mode : usize) -> isize
pub sys_read := @abi(syscall) fn(num : usize, fd : usize, buf : usize, n : usize) -> isize
pub sys_close := @abi(syscall) fn(num : usize, fd : usize) -> isize
## `sys_lseek` (num 8): lseek(fd, off, whence) — reposition the fd offset; returns the resulting
## absolute offset (or < 0). Used by `parser::embed` to size a file (whence 2 = SEEK_END → the byte
## length) and rewind it (whence 0 = SEEK_SET) before reading its bytes into the compile arena.
pub sys_lseek := @abi(syscall) fn(num : usize, fd : usize, off : usize, whence : usize) -> isize

## Process syscalls — the as/ld invocation a self-hosted DRIVER needs to turn its emitted GAS into
## an executable on its own. Raw Linux x86_64 numbers, no libc: `sys_fork` (57; no
## args, returns child pid in the parent / 0 in the child / < 0 on error), `sys_execve` (59;
## execve(path, argv, envp) — only RETURNS on failure), `sys_wait4` (61; wait4(pid, &status, 0, 0)),
## `sys_exit` (60; the child's escape hatch when execve fails).
pub sys_fork := @abi(syscall) fn(num : usize) -> isize
pub sys_execve := @abi(syscall) fn(num : usize, path : usize, argv : usize, envp : usize) -> isize
pub sys_wait4 := @abi(syscall) fn(num : usize, pid : isize, status : usize, opts : usize, rusage : usize) -> isize
pub sys_exit := @abi(syscall) fn(num : usize, code : usize) -> isize
## `sys_getpid` (39; no args) — a per-process unique-ish token for temp file names (parallel
## `alatyr run` invocations must not share one fixed temp exe path).
pub sys_getpid := @abi(syscall) fn(num : usize) -> isize

## `pipe2` (syscall 293): pipe2(&int fds[2], flags) — fills two 4-byte file descriptors at `fds`
## (read end first, write end second) and returns 0, or < 0 on error. `run` creates it with
## `O_CLOEXEC` (0o2000000 = 524288) so the kernel closes the write end AT a SUCCESSFUL execve: the
## parent then reads EOF and knows the program actually started. This is the only reliable way to
## tell "the child could not be exec'd" from "the child ran and exited 127" — the child's exit
## status alone cannot carry that distinction (a program may legitimately exit 127).
pub sys_pipe2 := @abi(syscall) fn(num : usize, fds : usize, flags : usize) -> isize

## Directory listing — `getdents64` (syscall 217): getdents64(fd, buf, count) fills `buf` with a run
## of `linux_dirent64` records and returns the bytes written (0 = end of directory, < 0 = error).
## A record is { d_ino:u64@0, d_off:u64@8, d_reclen:u16@16, d_type:u8@18, d_name:NUL-string@19 };
## advance by `d_reclen` to the next. The self-hosted `build` uses it to discover a package's `.al`
## modules (the lean dual of the Rust seed's `std::fs::read_dir`).
pub sys_getdents64 := @abi(syscall) fn(num : usize, fd : usize, buf : usize, count : usize) -> isize

## Read the target of a symbolic link — `readlink` (syscall 89): readlink(path, buf, bufsize) writes
## up to `bufsize` bytes of the link target into `buf` (NOT NUL-terminated) and returns the byte
## count (< 0 on error). The self-hosted compiler reads `/proc/self/exe` (a kernel symlink to its own
## binary) to locate its shipped `lib/` stdlib for ambient injection.
pub sys_readlink := @abi(syscall) fn(num : usize, path : usize, buf : usize, bufsize : usize) -> isize

## Create a directory — `mkdir` (syscall 83): mkdir(path, mode) — `path` a NUL-terminated C-string
## address, `mode` the permission bits (0755 = 493). Returns 0 on success, < 0 on error (e.g.
## -EEXIST if it already exists). The self-hosted `new` uses it to scaffold a package directory.
pub sys_mkdir := @abi(syscall) fn(num : usize, path : usize, mode : usize) -> isize

## Write the whole `[buf, buf+len)` byte range to the file at the NUL-terminated C-string address
## `path_cstr`, creating/truncating it (O_WRONLY|O_CREAT|O_TRUNC = 1|64|512 = 577, mode 0644 = 420).
## The output counterpart of the driver's `read_file_into`; returns 0 on success, < 0 on error.
pub write_file := fn(path_cstr : usize, buf : usize, len : usize) -> isize {
  fd := sys_open(2, path_cstr, 577, 420)
  if fd < 0 { return fd }
  ufd := unchecked bitcast(usize, fd)
  mut off := 0
  while off < len {
    nw := sys_write(1, ufd, buf + off, len - off)
    if nw <= 0 { cc := sys_close(3, ufd); return -1 }
    off += unchecked bitcast(usize, nw)
  }
  cc := sys_close(3, ufd)
  return 0
}

## The FOUR genuinely different outcomes of "spawn a toolchain program and wait for it". The old
## `run` returned one `isize` that folded them all into "non-zero", and every caller in `cli.al`
## then attributed the failure to the program's INPUT — so a driver defect (a malformed `envp`
## made `execve` fail EFAULT and the child exit 127) was reported for weeks as
## "the assembler (`as`) rejected the emitted assembly", on assembly `as` never read.
##
## `kind` = 0 — the program RAN; `code` is its raw `wait4` status word (0 = a clean exit 0).
## `kind` = 1 — the program could NOT BE SPAWNED; `code` is the `execve` errno as the kernel
##              returned it (negative). Nothing about the input is implied.
## `kind` = 2 — `fork` failed; `code` is fork's return.
## `kind` = 3 — `wait4` failed; `code` is wait4's return.
## `kind` = 4 — the exec-status pipe could not be created; `code` is `pipe2`'s return.
pub Spawned := struct { kind : usize, code : isize }

## Spawn `path_cstr` (an ABSOLUTE NUL-terminated program path) with the NUL-terminated pointer array
## `argv` (each entry a C-string address; the array ends in a 0 word) and environment `envp` (same
## shape, may be a pointer to a single 0 word for an empty env); block until it exits; return a
## classified `Spawned` (see above). fork -> child execve (on failure it reports the errno through a
## CLOEXEC pipe and exits 127) -> parent wait4 -> parent reads the pipe.
pub run := fn(in out a : Arena, path_cstr : usize, argv : usize, envp : usize) -> Spawned {
  ## The exec-status pipe. `pipe2` writes two 4-byte descriptors into one 8-byte slot; they are
  ## split out with unsigned `/` and `%` (2^32) rather than shifts, which the lean lower emits as
  ## the plain `divq`/`mulq` pair it already uses for `push_int`.
  fds := bump(a, 8)
  fp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), fds)
  deref(fp) = 0
  pr := sys_pipe2(293, fds, 524288)
  if pr < 0 { return Spawned(kind = 4, code = pr) }
  fw := deref(fp)
  rfd := fw % 4294967296
  wfd := fw / 4294967296
  ## Both slots are bumped BEFORE the fork so the child writes its errno out of an address the
  ## parent also knows; the value itself travels through the PIPE, not through the (copy-on-write,
  ## therefore private) memory.
  eb := bump(a, 8)
  ep : ptr(mut usize) = unchecked bitcast(ptr(mut usize), eb)
  deref(ep) = 0
  sp := bump(a, 8)
  sw : ptr(mut usize) = unchecked bitcast(ptr(mut usize), sp)
  deref(sw) = 0
  pid := sys_fork(57)
  if pid < 0 {
    c1 := sys_close(3, rfd)
    c2 := sys_close(3, wfd)
    return Spawned(kind = 2, code = pid)
  }
  if pid == 0 {
    cr := sys_close(3, rfd)
    ee := sys_execve(59, path_cstr, argv, envp)
    ## execve RETURNED, so it failed: hand the errno to the parent and exit 127.
    deref(ep) = unchecked bitcast(usize, ee)
    nw := sys_write(1, wfd, eb, 8)
    xx := sys_exit(60, 127)
    return Spawned(kind = 1, code = ee)
  }
  cw := sys_close(3, wfd)
  w := sys_wait4(61, pid, sp, 0, 0)
  ## Every write end is closed by now (the parent's above, the child's by CLOEXEC-at-exec or by its
  ## exit), so this read never blocks: 8 bytes = the child could not be exec'd, EOF = it ran.
  nr := sys_read(0, rfd, eb, 8)
  cr := sys_close(3, rfd)
  if nr == 8 { return Spawned(kind = 1, code = i64(deref(ep))) }
  if w < 0 { return Spawned(kind = 3, code = w) }
  return Spawned(kind = 0, code = i64(deref(sw)))
}

## A growable byte buffer — the emitter's output sink (the lean stand-in for `alloc::strbuf`).
## `data` is the arena address of the byte block, `len` the bytes written, `cap` the reserved
## byte capacity. Bytes are stored one word at a time at byte offsets: a word store writes the
## byte plus 7 trailing zeros, the next append overwrites them, and `sb_flush` emits only
## `[0, len)` — so the flushed bytes are exact (reserve a few bytes of slack in `cap`).
## (The GAS emitter's GLOBAL label counter is NOT here — it is threaded as a scalar `in out nl`
## param through the emit recursion; a scalar out-param now writes back to the
## caller, so the counter accumulates across `emit_fn` calls without living on the buffer.)
pub StrBuf := struct { data : ptr(mut u8), len : usize, cap : usize }

## Append one byte `b` (its low 8 bits); returns the new length. A word store writes the byte
## plus 7 trailing zeros that the next append overwrites, so the buffer must keep ≥ 8 bytes of
## slack past `len` — overflow is a hard error (the lean stand-in for `alloc::strbuf`'s growth;
## the emitter sizes its output buffer up front fixpoint).
pub sb_byte := fn(in out s : StrBuf, b : usize) -> usize {
  if s.len + 8 > s.cap { panic("rt: StrBuf overflow") }
  p : ptr(mut usize) = unchecked bitcast(ptr(mut usize), s.data + s.len)
  deref(p) = b
  s.len = s.len + 1
  return s.len
}

## Construct a `StrBuf` with `cap` bytes reserved from the bump arena `a` (the `alloc::strbuf::strbuf`
## analogue). The data block is a freestanding region of `a`; the buffer never grows, so `cap`
## must exceed the largest output (the emitter sizes it from the source length).
pub strbuf := fn(in out a : Arena, cap : usize) -> StrBuf {
  ## `a` is taken `in out` (not `ptr(mut Arena)`): forwarding the in-out arena to `bump` reserves
  ## from the CALLER's live arena (off propagates back). The old `bump(deref(a), cap)` over a
  ## `ptr(mut Arena)` MISCOMPILED under the self-host lower — `deref(a)` as a call argument
  ## materialized a STALE copy of the 3-word arena (its `off` word read pre-update), so the buffer
  ## was reserved at the wrong offset and overlapped earlier records. The in-out forward (the same
  ## shape as `vec_push`/the in-loop `bump`) lowers correctly under both compilers.
  d := bump(a, cap)
  return StrBuf(data = unchecked bitcast(ptr(mut u8), d), len = 0, cap = cap)
}

## The `alloc::strbuf` output-surface analogues the emitter calls (`push_str`/`push_int` are the
## bare names `lower.al` imports; `push_byte`/`buf_len`/`strbuf_base`/`strbuf_free` are used by
## the driver). `push_str` appends a string's bytes (== `sb_str`); `push_int` formats a signed
## decimal; `strbuf_base` is the buffer's data address (for resolving emitted spans).
pub push_str := fn(in out s : StrBuf, x : str) -> usize { return sb_str(s, x) }
pub push_byte := fn(in out s : StrBuf, b : u8) -> usize { return sb_byte(s, usize(b)) }
## Render `n` as UNSIGNED decimal, most-significant digit first.
##
## The recursion guard is `n / 10 != 0`, NOT `n >= 10`. `/` and `%` on a `usize` already lower to the
## UNSIGNED `divq`, but an ORDERING comparison whose other operand is an integer LITERAL is lowered
## with the SIGNED setcc: `is_unsigned_cmp` (lower.al) demands BOTH operands be PROVABLY unsigned and
## a literal carries no type span, so `n >= 10` emitted `setge`. For `n >= 2^63` the guard therefore
## read the value as negative, the recursion never ran, and a single digit came out — `push_int` of
## `i64::MIN` rendered "-8" instead of "-9223372036854775808", so the source literal `2**63` was
## SILENTLY materialized as the immediate `$-8` in the emitted GAS (Types §9.1/§11: an integer
## literal's value is its written value; a wrong one is a silent miscompile). An `!= 0` test is an
## EQUALITY compare (`setne`) — signedness-independent — so this renderer is correct across the whole
## u64 range regardless of how the ordering setcc is chosen. Byte-identical output for every value
## the self-build actually renders (all < 2^63), hence fixpoint-neutral.
sb_uint := fn(in out s : StrBuf, n : usize) {
  q := n / 10
  if q != 0 { sb_uint(s, q) }
  d := sb_byte(s, n % 10 + 48)
}
pub push_int := fn(in out s : StrBuf, n : i64) -> usize {
  if n < 0 {
    nb := sb_byte(s, 45)
    sb_uint(s, unchecked bitcast(usize, 0 - n))
    return s.len
  }
  sb_uint(s, unchecked bitcast(usize, n))
  return s.len
}
## `s` is taken `in out StrBuf` (not `ptr(StrBuf)` + `deref(s).field`): the self-host parser
## discards a `ptr(StrBuf)` param's POINTEE type, so `deref(s).data`/`.len` could not resolve the
## field offset and lowered to ZERO (the type-discard cluster). A by-ref `StrBuf` param carries the
## struct type, so `s.data`/`s.len` resolve — exactly as `sb_byte`'s `in out s : StrBuf` already does.
pub buf_len := fn(in out s : StrBuf) -> usize { return s.len }
pub strbuf_base := fn(in out s : StrBuf) -> ptr(mut u8) { return s.data }
pub strbuf_free := fn(s : StrBuf) -> isize { return 0 }

## Append every byte of the string `x`; returns the new length. The loop bound is the str's
## byte length `x.len` (the `{ptr,len}` field — spec `byte_len`), and each byte is read via the
## spec-canonical `bytes(x)[i]`. Both spellings lower as the same operation under BOTH Stage-0
## and the self-host lower, so the emitter's `push_str` (copy a literal/source `str` into the
## output) works consistently across compilers.
pub sb_str := fn(in out s : StrBuf, x : str) -> usize {
  for i in 0 .. x.len {
    np := sb_byte(s, bytes(x)[i])
  }
  return s.len
}

## Flush the buffer's `[0, len)` bytes to file descriptor `fd` (the assembled output).
pub sb_flush := fn(s : StrBuf, fd : usize) -> isize {
  return sys_write(1, fd, unchecked bitcast(usize, s.data), s.len)
}
