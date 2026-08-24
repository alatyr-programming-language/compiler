## std::io — output surface (Stdlib §7 / §2.7).
##
## v1 slice: the Linux `write` syscall plus `str`/`[u8]` output to the standard
## streams. This is the first member of the **std tier** — an ambient root module
## `std` the compiler provides (Stdlib §1; not a manifest dependency), reached
## qualified (`std::io::print(...)`) or bound (`p := std::io::print`). It is absent
## under the `freestanding` limit.
##
## The full `Writer` protocol object and `File` land incrementally on top of this;
## the `Result(_, IoError)` error layer and `read`/`write`-with-`Result` are here.

## The Linux `write(2)` syscall through the `@abi(syscall)` convention (ABI §5 /
##): the number → the number register, the arguments → the argument registers,
## the result ← the result register (a negative value is `-errno`). Body-less; each
## call lowers to the `syscall` trap. Raw-level, so callers wrap it in `unchecked`.
sys_write := @abi(syscall) fn(num : usize, fd : usize, buf : ptr(u8), len : usize) -> isize

## The Linux `read(2)` syscall (number `0`): read up to `len` bytes from `fd` into
## the buffer at `buf`, result ← bytes read (`0` = EOF) or a negative `-errno`.
sys_read := @abi(syscall) fn(num : usize, fd : usize, buf : ptr(mut u8), len : usize) -> isize

## Write a byte slice to a file descriptor; returns the raw syscall result (the
## byte count written, or a negative `-errno`). The slice's pointer/length go
## straight to the syscall, so no copy occurs (I1/I2). `1` is the `write` number.
pub write_fd := fn(fd : usize, buf : [u8]) -> isize {
  unchecked sys_write(1, fd, buf.ptr, buf.len)
}

## Write a string to standard output (fd 1). Returns the byte count written (or
## a negative `-errno`).
pub print := fn(s : str) -> isize {
  write_fd(1, bytes(s))
}

## Write a string to standard error (fd 2).
pub eprint := fn(s : str) -> isize {
  write_fd(2, bytes(s))
}

## --- The `Result(_, IoError)` error layer (Stdlib §7) ----------------------
## Every std call that can fail surfaces its failure as `Result(_, IoError)` — no
## hidden failure (I11/I3). `IoError` is the std-tier enum with a **closed v1 set**
## (mirrors the spec exactly): a failure not separately classified maps to
## `Other(raw errno)`, never a new variant, so an exhaustive `match` stays valid
## across the frozen version (a new named variant would be a versioned, breaking
## change). `TimedOut`/`ConnectionRefused` are present ahead of networking.
pub IoError := enum {
  NotFound, PermissionDenied, AlreadyExists, InvalidInput, UnexpectedEof,
  Interrupted, WouldBlock, BrokenPipe, TimedOut, ConnectionRefused,
  Other(i32),
}

## Map a raw Linux `errno` (a **positive** code — the negation of a failed
## syscall's negative return) to the matching `IoError` variant; an unclassified
## code carries through verbatim as `Other(code)`. The codes are the Linux/x86_64
## numbers (`ENOENT` 2, `EPERM` 1 / `EACCES` 13, `EEXIST` 17, `EINVAL` 22, `EINTR`
## 4, `EAGAIN` 11, `EPIPE` 32, `ETIMEDOUT` 110, `ECONNREFUSED` 111). `UnexpectedEof`
## is not a raw `errno` (it is a logical short read), so it is never produced here.
pub io_error := fn(e : i32) -> IoError {
  if e == 1   { return IoError.PermissionDenied }
  if e == 2   { return IoError.NotFound }
  if e == 4   { return IoError.Interrupted }
  if e == 11  { return IoError.WouldBlock }
  if e == 13  { return IoError.PermissionDenied }
  if e == 17  { return IoError.AlreadyExists }
  if e == 22  { return IoError.InvalidInput }
  if e == 32  { return IoError.BrokenPipe }
  if e == 110 { return IoError.TimedOut }
  if e == 111 { return IoError.ConnectionRefused }
  IoError.Other(e)
}

## Build a failed Result directly from the raw errno. Keep every payload as a nested enum LITERAL:
## `Result(T, IoError).Err(io_error(e))` is a multi-word enum CALL payload and therefore remains on
## the generic-enum ABI frontier. This helper is generic over the success type so File/open and
## usize/io_result share the same literal-only construction path.
pub io_error_result := fn(T : type, e : i32) -> Result(T, IoError) {
  if e == 1   { return Result(T, IoError).Err(IoError.PermissionDenied) }
  if e == 2   { return Result(T, IoError).Err(IoError.NotFound) }
  if e == 4   { return Result(T, IoError).Err(IoError.Interrupted) }
  if e == 11  { return Result(T, IoError).Err(IoError.WouldBlock) }
  if e == 13  { return Result(T, IoError).Err(IoError.PermissionDenied) }
  if e == 17  { return Result(T, IoError).Err(IoError.AlreadyExists) }
  if e == 22  { return Result(T, IoError).Err(IoError.InvalidInput) }
  if e == 32  { return Result(T, IoError).Err(IoError.BrokenPipe) }
  if e == 110 { return Result(T, IoError).Err(IoError.TimedOut) }
  if e == 111 { return Result(T, IoError).Err(IoError.ConnectionRefused) }
  Result(T, IoError).Err(IoError.Other(e))
}

## Turn a raw syscall return (`>= 0` a byte count, `< 0` a `-errno`) into a
## `Result(usize, IoError)`: the shared shape every fallible read/write lowers
## through. A negative return is negated back to `errno` and mapped (§7).
io_result := fn(r : isize) -> Result(usize, IoError) {
  if r < 0 {
    e := i32(0 - r)
    return io_error_result(usize, e)
  }
  Result(usize, IoError).Ok(usize(r))
}

## Write a byte slice to `fd`, returning `Ok(bytes_written)` or the mapped
## `IoError` — the fallible counterpart of `write_fd` (which returns the raw
## result). The slice goes straight to the syscall (no copy, I1/I2).
pub write := fn(fd : usize, buf : [u8]) -> Result(usize, IoError) {
  r := unchecked sys_write(1, fd, buf.ptr, buf.len)
  io_result(r)
}

## Read up to `len` bytes from `fd` into the buffer at `buf`, returning
## `Ok(bytes_read)` (`Ok(0)` = end of input) or the mapped `IoError`.
pub read := fn(fd : usize, buf : ptr(mut u8), len : usize) -> Result(usize, IoError) {
  r := unchecked sys_read(0, fd, buf, len)
  io_result(r)
}

## Read up to `len` bytes of standard input (fd 0) into the buffer at `buf`.
pub read_stdin := fn(buf : ptr(mut u8), len : usize) -> Result(usize, IoError) {
  read(0, buf, len)
}

## --- Files (Stdlib §7) -----------------------------------------------------
## `File` — an open OS file: a thin handle over its descriptor. v1 surface:
## `open` → `Result(File, IoError)`, then `file_read` / `file_write` / `file_seek`
## / `file_close` (each fallible through the `Result`/`IoError` layer). It is a
## plain value (the spec does not mark `File` linear); closing is explicit.
pub File := struct { fd : i32 }

## The Linux `open(2)` (number `2`), `close(2)` (`3`), and `lseek(2)` (`8`)
## syscalls (Linux x86_64). Raw-level, wrapped in `unchecked` by the callers.
sys_open := @abi(syscall) fn(num : usize, path : ptr(u8), flags : usize, mode : usize) -> isize
sys_close := @abi(syscall) fn(num : usize, fd : usize) -> isize
sys_lseek := @abi(syscall) fn(num : usize, fd : usize, off : isize, whence : usize) -> isize

## Open flags (the Linux/x86_64 numeric values), as the `mode` argument to
## `open`: read-only / write-only / read-write, OR-combined with create /
## truncate / append. (`O_CREAT` uses mode `0644` for a newly created file.)
pub O_RDONLY := 0
pub O_WRONLY := 1
pub O_RDWR   := 2
pub O_CREAT  := 64
pub O_TRUNC  := 512
pub O_APPEND := 1024

## Open `path` with the given `flags` (an OR of the `O_*` values), returning the
## opened `File` or the mapped `IoError`. The `str` path is copied into a
## NUL-terminated stack buffer (a `str` carries no terminator); a path of 255+
## bytes is rejected as `InvalidInput` (the v1 fixed buffer). A newly created
## file (`O_CREAT`) gets mode `0644` (`420`).
pub open := fn(path : str, flags : i32) -> Result(File, IoError) {
  bs := bytes(path)
  if bs.len >= 256 {
    return Result(File, IoError).Err(IoError.InvalidInput)
  }
  mut cpath : [u8; 256] = [0; 256]
  mut i : usize = 0
  while i < bs.len {
    b := bs[i]
    cpath[i] = b
    i += 1
  }
  fl := usize(bitcast(u32, flags))
  r := unchecked sys_open(2, ptr(cpath[0]), fl, 420)
  if r < 0 {
    e := i32(0 - r)
    return io_error_result(File, e)
  }
  Result(File, IoError).Ok(File(fd = i32(r)))
}

## Read up to `len` bytes from the open file into the buffer at `buf`;
## `Ok(bytes_read)` (`Ok(0)` = end of file) or the mapped `IoError`.
pub file_read := fn(f : File, buf : ptr(mut u8), len : usize) -> Result(usize, IoError) {
  fd := usize(bitcast(u32, f.fd))
  r := unchecked sys_read(0, fd, buf, len)
  io_result(r)
}

## Write a byte slice to the open file; `Ok(bytes_written)` or the mapped error.
pub file_write := fn(f : File, buf : [u8]) -> Result(usize, IoError) {
  fd := usize(bitcast(u32, f.fd))
  r := unchecked sys_write(1, fd, buf.ptr, buf.len)
  io_result(r)
}

## Seek to the absolute byte offset `pos` (whence `SEEK_SET` = 0); `Ok(offset)`.
pub file_seek := fn(f : File, pos : usize) -> Result(usize, IoError) {
  fd := usize(bitcast(u32, f.fd))
  off := bitcast(isize, pos)
  r := unchecked sys_lseek(8, fd, off, 0)
  io_result(r)
}

## Close the open file's descriptor; `Ok(0)` on success or the mapped error.
pub file_close := fn(f : File) -> Result(usize, IoError) {
  fd := usize(bitcast(u32, f.fd))
  r := unchecked sys_close(3, fd)
  io_result(r)
}

## Write a whole byte slice to a file at `path`, creating it (mode 0644) and
## truncating any existing contents (`O_WRONLY | O_CREAT | O_TRUNC` = 1|64|512 =
## 577), then **closing** it (so the bytes are flushed to disk before any reader —
## e.g. `as` — opens the file). Returns `Ok(bytes_written)` or the mapped
## `IoError`. This is the primitive a self-hosted compiler needs to put its emitted
## GAS on disk for the assembler (the toolchain-drive loop). One `write(2)`
## (partial-write looping is additive; a freshly created file accepts the buffer in
## one call for the sizes here).
pub write_file := fn(path : str, buf : [u8]) -> Result(usize, IoError) {
  f := open(path, 577)?
  wr := file_write(f, buf)
  mut n : usize = 0
  match wr {
    Result::Ok(c) => { n = c }
    Result::Err(e) => {
      cc := file_close(f)
      return Result(usize, IoError).Err(e)
    }
  }
  file_close(f)?
  Result(usize, IoError).Ok(n)
}

## --- Minimal scalar rendering (Stdlib §2.7 v1 layer) -----------------------
## Render a scalar to its textual bytes and write it straight to stdout — no
## allocation, no format string (output composes by sequential writes). The
## `format("{}", …)` template and `Display` over aggregates are additive (they
## need comptime-variadics and `typeinfo` respectively).

## Write a single byte to standard output (through a one-element buffer, since a
## syscall takes a pointer + length).
write_byte := fn(c : u8) -> isize {
  buf : [u8; 1] = [c]
  unchecked sys_write(1, 1, ptr(buf[0]), 1)
}

## Print an unsigned integer in base-10, most-significant digit first (recursive:
## the high part is printed before this digit). `0` prints as "0".
pub print_uint := fn(n : u64) -> isize {
  if n >= 10 {
    print_uint(n / 10)
  }
  write_byte(u8(n % 10 + 48))
}

## Print a signed integer in base-10, with a leading '-' for a negative value.
pub print_int := fn(n : i64) -> isize {
  if n < 0 {
    write_byte(45)
    bits := bitcast(u64, n)
    ## Compute the magnitude without evaluating the unrepresentable signed negation:
    ## u64::MAX - bits is at most u64::MAX - 2^63, so the final +1 is safe even
    ## for i64::MIN, whose magnitude is 2^63.
    magnitude := 18446744073709551615 - bits + 1
    return print_uint(magnitude)
  }
  print_uint(bitcast(u64, n))
}
