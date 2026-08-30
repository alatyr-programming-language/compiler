## std::term — standard streams (Stdlib §7).
##
## A stream is an explicit file-descriptor value. The v1 surface is Linux
## x86_64 only, follows std::io's concrete Result/IoError contract, and does
## not promise terminal detection, line editing, or platform portability.

pub Stream := struct { fd : usize }

## Standard output and standard error. The descriptors are conventional process
## inputs on the supported Linux target; a caller can still receive an I/O error
## when writing to them.
pub stdout := fn() -> Stream { Stream(fd = 1) }
pub stderr := fn() -> Stream { Stream(fd = 2) }

## Write bytes to the selected stream. A successful write may be short; the
## returned count is therefore part of the API contract.
pub write := fn(stream : Stream, buf : [u8]) -> Result(usize, io::IoError) {
  io::write(stream.fd, buf)
}

## Write UTF-8 bytes to the selected stream without allocating. This is a
## convenience wrapper over `write` and preserves the same partial-write/error
## behavior.
pub write_str := fn(stream : Stream, text : str) -> Result(usize, io::IoError) {
  write(stream, bytes(text))
}
