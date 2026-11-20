- The shared IR builder now builds `str_at(p, n)` with the two operations that surround it in a
  source scanner: byte-pointer arithmetic `p + n` and `==` / `!=` over `str` (#980, slice IR-36).
  - `str_at` is the raw view of `n` bytes at `p` (Stdlib appendix §3.6).
  - `p + n` is built for a pointee that is a one-byte integer and an unsigned offset, the one shape
    where a byte offset and an element offset are the same address (spec#170 asks which one the
    language means for a wider pointee).
  - `str` equality compares lengths, then bytes (STD-4).
  The builder now builds 370 more of the compiler's own functions (1353 of 5299 to 1723 of 5312), which
  x86_64 takes from the IR rather than from the legacy emitter. It also fixes, for every function
  the IR now builds, a silent wrong value of the legacy emitter: there, `unchecked str_at(…)` was
  not recognised as a view (#1782). Every shape left out is refused with a cause of its own: another
  operator, a wider or unspelled pointee, a signed offset, a `usize` address for `str_at`, and an
  equality of other views.
