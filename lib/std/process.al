## std::process — spawning child processes (Stdlib §7).
##
## The OS process primitives via `@abi(syscall)` (Linux x86_64): `fork(2)` = 57,
## `execve(2)` = 59, `wait4(2)` = 61. Raw-level, so each wrapper is `unchecked`.
## This is the surface a self-hosted compiler needs to invoke `as`/`ld` itself
## (the reproducible-build fixpoint): build an argv, `fork`, `execve` in the
## child, `wait4` the child in the parent, decode its exit status.
##
## Mirrors the `@abi(syscall)` pattern of `std::os` (mmap/munmap) and
## `base::process` (exit): a body-less `@abi(syscall) fn(num, args…) -> isize`
## lowers each call to the `syscall` trap (param0 → rax, rest → rdi, rsi, …).
## Pointer arguments are passed as `usize` (native pointer width — never `u64`,
## so the std blob type-checks on every arch).

## `fork(2)` (57): no arguments beyond the number. Returns the child's pid in the
## parent, `0` in the child, and a negative `-errno` on error.
sys_fork := @abi(syscall) fn(num : usize) -> isize

## `execve(2)` (59): replace the calling process image. `path` is a pointer to a
## NUL-terminated pathname; `argv` and `envp` are pointers to NULL-terminated
## arrays of NUL-terminated-string pointers. On success it does NOT return (the
## image is replaced); on failure it returns `-errno`.
sys_execve := @abi(syscall) fn(num : usize, path : usize, argv : usize, envp : usize) -> isize

## `wait4(2)` (61): wait for state changes in child `pid`. `status` is a pointer
## to an `int` that receives the wait status; `options` is a flag set (`0` =
## block); `rusage` is a pointer to a `struct rusage` or NULL. Returns the pid of
## the child whose state changed, or `-errno`.
sys_wait4 := @abi(syscall) fn(num : usize, pid : usize, status : usize, options : usize, rusage : usize) -> isize

## --- cstring / argv helpers --------------------------------------------------
## An Alatyr `str` is `{ptr, len}` and is NOT NUL-terminated; `execve` needs C
## NUL-terminated strings and a NULL-terminated array of their pointers. These
## helpers copy into a caller-provided allocator (arena, region-backed) — the
## established raw-memory pattern from `std::os::args`. `usize` pointers throughout.

## Copy `s` into the arena as a NUL-terminated C string. Allocates `len + 1`
## bytes, copies the `len` bytes of `s`, writes a trailing `0`, and returns the
## **raw address** of the first byte (a `usize`, the `char*` `execve` wants).
## Traps on allocator exhaustion (the trapping convenience; a recoverable form is
## additive).
pub cstring := fn(a : ptr(mut Arena), s : str) -> usize {
  bs := bytes(s)
  n := bs.len
  rb := allocate(deref(a), u8, n + 1, 1)
  mut bidx : usize = 0
  match rb {
    Result::Ok(h) => { bidx = h.idx }
    Result::Err(e) => { panic("cstring: allocator out of memory") }
  }
  aa := deref(a)
  base := get(u8, aa, Handle(u8)(idx = bidx))
  dst := unchecked bitcast(usize, base)
  src := unchecked bitcast(usize, bs.ptr)
  mut i : usize = 0
  while i < n {
    sb := unchecked bitcast(ptr(u8), src + i)
    db := unchecked bitcast(ptr(mut u8), dst + i)
    deref(db) = deref(sb)
    i += 1
  }
  term := unchecked bitcast(ptr(mut u8), dst + n)
  deref(term) = 0
  return dst
}

## Build a NULL-terminated array of `char*` (an `argv`/`envp`) in the arena from a
## slice of cstring pointers. Allocates `count + 1` words: each element is the
## corresponding cstring pointer, the last word is `0` (the NULL terminator).
## Returns the raw address of element 0 (the `char**` `execve` wants).
pub ptr_array := fn(a : ptr(mut Arena), ptrs : Slice(usize)) -> usize {
  count := ptrs.len
  stride : usize = 8
  rb := allocate(deref(a), u8, (count + 1) * stride, 8)
  mut bidx : usize = 0
  match rb {
    Result::Ok(h) => { bidx = h.idx }
    Result::Err(e) => { panic("ptr_array: allocator out of memory") }
  }
  aa := deref(a)
  base := get(u8, aa, Handle(u8)(idx = bidx))
  dst := unchecked bitcast(usize, base)
  mut i : usize = 0
  while i < count {
    slot := unchecked bitcast(ptr(mut usize), dst + i * stride)
    deref(slot) = ptrs[i]
    i += 1
  }
  nullslot := unchecked bitcast(ptr(mut usize), dst + count * stride)
  deref(nullslot) = 0
  return dst
}

## --- exit-status decoding ----------------------------------------------------
## A `wait4` status word packs the cause of the change. For a normally-exited
## child the low byte is `0` and the next byte is the exit code: the exit code is
## `(status >> 8) & 0xff` (Linux `WEXITSTATUS`). For a signal-killed child the low
## 7 bits carry the signal number. These mirror the libc `<sys/wait.h>` macros.
## (The language has no shift operator, so `>> 8` is `/ 256`.)

## The exit code of a normally-exited child: `(status / 256) & 0xff`.
pub exit_status := fn(status : usize) -> usize {
  return unchecked (status / 256) & 255
}

## Whether the child exited normally (low byte `0`): `(status & 0x7f) == 0`.
pub exited := fn(status : usize) -> bool {
  return unchecked (status & 127) == 0
}

## --- spawn / run -------------------------------------------------------------

## Spawn `path` with arguments `args` (the slice of cstring-able arguments that
## become `argv[1..]`; `argv[0]` is `path` itself), wait for it, and return its
## **decoded exit code** (`0..=255`) on a normal exit, or `-1` on a fork/exec/wait
## error or an abnormal (signalled) termination.
##
## The child inherits the parent's stdin/stdout/stderr, so a spawned program's
## output appears on the parent's streams (output capture via a pipe is additive,
## deferred). `envp` is an empty NULL-terminated array (the child runs with an
## empty environment — enough for `as`/`ld` invoked with absolute paths and
## explicit flags; inheriting `environ` is additive).
##
## The arena `a` backs the cstrings and the argv/envp arrays; they live for the
## arena's extent (region-backed).
pub run := fn(path : str, args : Slice(str), a : ptr(mut Arena)) -> isize {
  pid := unchecked sys_fork(57)
  neg1 : isize = 0 - 1
  if pid < 0 {
    ## fork failed.
    return neg1
  }
  if pid == 0 {
    ## In the CHILD: build argv (path + args + NULL), then execve.
    path_c := cstring(a, path)
    argc := args.len
    ## argv has `argc + 1` real entries (path then each arg). Build the cstring
    ## pointer table in the arena, then NULL-terminate it via `ptr_array`.
    stride : usize = 8
    rb := allocate(deref(a), u8, (argc + 1) * stride, 8)
    mut bidx : usize = 0
    match rb {
      Result::Ok(h) => { bidx = h.idx }
      Result::Err(e) => { exit(127) }
    }
    aa := deref(a)
    base := get(u8, aa, Handle(u8)(idx = bidx))
    tbase := unchecked bitcast(usize, base)
    p0 := unchecked bitcast(ptr(mut usize), tbase)
    deref(p0) = path_c
    mut i : usize = 0
    while i < argc {
      ac := cstring(a, args[i])
      slot := unchecked bitcast(ptr(mut usize), tbase + (i + 1) * stride)
      deref(slot) = ac
      i += 1
    }
    argv_ptrs := Slice(usize)(ptr = unchecked bitcast(ptr(usize), tbase), len = argc + 1)
    argv := ptr_array(a, argv_ptrs)
    empty_ptrs := Slice(usize)(ptr = unchecked bitcast(ptr(usize), tbase), len = 0)
    envp := ptr_array(a, empty_ptrs)
    ## execve replaces the image; if it returns, exec failed → exit with 127.
    er := unchecked sys_execve(59, path_c, argv, envp)
    exit(127)
  }
  ## In the PARENT: wait4(pid, &status, 0, 0), decode the exit code. The status
  ## output word lives in the arena (taking `ptr` of a bare scalar local is
  ## not a place; the arena slot is, via its raw address — the established idiom).
  rs := allocate(deref(a), usize, 1, 8)
  mut sidx : usize = 0
  match rs {
    Result::Ok(h) => { sidx = h.idx }
    Result::Err(e) => { return neg1 }
  }
  aa := deref(a)
  sbase := get(usize, aa, Handle(usize)(idx = sidx))
  sp := unchecked bitcast(usize, sbase)
  sw := unchecked bitcast(ptr(mut usize), sp)
  deref(sw) = 0
  wr := unchecked sys_wait4(61, bitcast(usize, pid), sp, 0, 0)
  if wr < 0 {
    return neg1
  }
  status := deref(sw)
  if exited(status) {
    return unchecked bitcast(isize, exit_status(status))
  }
  return neg1
}
