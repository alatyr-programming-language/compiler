## std::argv — borrowed process arguments (Stdlib §7).
##
## The kernel command line is read at call time into caller-owned storage. These
## functions expose the non-allocating layer of std::os: no process-global
## buffer, hidden arena, or implicit copy is introduced. `buf` must point to at
## least `cap` writable bytes for `read`; the returned slices borrow that buffer.

## Fill `buf` with the program name and arguments as NUL-separated byte strings.
## The return value is the number of bytes read; zero means the OS source could
## not be read or the process has an empty command line.
pub read := fn(buf : ptr(mut u8), cap : usize) -> usize {
  os::read_cmdline(buf, cap)
}

## Count the NUL-separated argument segments in the first `len` bytes of `buf`.
pub count := fn(buf : ptr(u8), len : usize) -> usize {
  os::seg_count(buf, len)
}

## Return the `idx`-th argument as a borrowed byte slice. An out-of-range index
## returns an empty slice. The view is valid only while `buf` remains live.
pub get := fn(buf : ptr(u8), len : usize, idx : usize) -> Slice(u8) {
  os::nth(buf, len, idx)
}
