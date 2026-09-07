## Checked-mode bounds trap for the OUTER element index of a MODULE-LEVEL `[str; N]` global
## (`G[k][j]`) — I11 §358, issue #495. The element pair is addressed at `LABEL + k*16`, so an
## out-of-range `k` would read the two words that follow the array in `.data`/`.rodata` and then
## dereference the first of them as a string pointer. `k` is compared against the STATIC element
## count N from the same layout query the image was emitted with (`cmpq $N, %rcx; jb; ud2`) ->
## SIGILL, exit 132. x86_64 (`run_x86`), dropped in an `unchecked` scope like every other index.
##
## FAILURE-FIRST: on the parent the element pair was never materialized at all — each element imaged
## as one `.quad 0`, and the nested read is refused by #425's tail — so no outer bound existed to trap
## and the row fails at compile/link. Before #425 it ran to a normal exit off frame slot 0.
##
## `k = 2` on a 2-element array is ONE past the end — the nearest possible miss, so a check that is
## off by one cannot pass. The inner index 0 is in range for every element, so the trap can only come
## from the OUTER bound.
G := ["abc", "XYZ"]
main := fn() -> u64 {
  k : u64 = 2
  return u64(G[k][0])
}
