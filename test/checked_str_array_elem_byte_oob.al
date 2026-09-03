## Checked-mode bounds trap for the inner BYTE index of a `str` ELEMENT of a `[str; N]` local
## (`arr[k][j]`) — I11 §358, issue #394. The element is a two-word `{ptr, len}` view (Types §7), so
## the inner index is checked against that element's RUNTIME len, not against a static N:
## `cmpq %rbx, %r8; jb; ud2` → SIGILL, exit 132. x86_64 (`run_x86`), dropped in an `unchecked` scope
## like every other view index.
##
## FAILURE-FIRST: on the parent this shape reached the untyped `emit_index_addr` tail, which resolved
## the unnamed `Index(arr, k)` base to frame SLOT 0 and read `-8(%rbp) + j*8` with no check at all —
## it ran to a normal exit, so the fixture failed with a wrong (non-trap) status before the fix.
##
## `j = 9` on `"ABCDEF"` (len 6) → trap. Element 1 is longer than element 0 so the check cannot be
## satisfied by reading the wrong element's length.
main := fn() -> u64 {
  arr : [str; 2] = ["ABCDEF", "uvwxyz01234"]
  j : u64 = 9
  return u64(arr[0][j])
}
