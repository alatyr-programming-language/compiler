## Checked-mode bounds trap for the INNER byte index of a `str` ELEMENT of a MODULE-LEVEL `[str; N]`
## global (`G[k][j]`) — I11 §358, issue #495. The element is a two-word `{ptr, len}` view (Types §7),
## so the inner index is checked against THAT ELEMENT's RUNTIME len, not against a static N:
## `cmpq %rbx, %r8; jb; ud2` -> SIGILL, exit 132. x86_64 (`run_x86`), dropped in an `unchecked` scope
## like every other view index. The same shared view-byte-index decision the LOCAL spelling uses, so
## the two roots cannot disagree about where the bound comes from.
##
## FAILURE-FIRST: on the parent this shape had no bounds check at all. Its `.data` image was one
## `.quad 0` per element (a str element has no scalar init value), and the read fell to the untyped
## `emit_index_addr` tail — a frame-slot-0 word before #425, a compile-time REFUSAL after it. So on
## the parent the row fails at compile/link, having never reached a runtime trap; before #425 it would
## have run to a normal exit carrying a frame word.
##
## `j = 9` on `"abc"` (len 3) -> trap. Element 1 is LONGER than element 0 (`"XYZ0123456789"`, len 13,
## so offset 9 is inside it), which means the check cannot be satisfied by reading the WRONG element's
## length, and the trap cannot be an accident of both elements being short.
G := ["abc", "XYZ0123456789"]
main := fn() -> u64 {
  j : u64 = 9
  return u64(G[0][j])
}
