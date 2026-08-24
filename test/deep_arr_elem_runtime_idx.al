## e2e — Types §9.4 DEEP aggregate array-element addressing at a RUNTIME index, on an explicitly
## UNINITIALIZED typed array local (`mut xs : [Row; 2]`, no initializer — the element type and count
## exist only in the source annotation). The existing deep fixtures all index with CONSTANTS, so this
## locks the composed address form itself: element base (i * element words) + field offset + inner
## index (j * element words), with BOTH indices runtime values.
##   - `xs[i].arr[j]` READ and WRITE (an index into an inline `[u64; 3]` FIELD of the element)
##   - `xs[i].inner.v` READ and WRITE (a nested STRUCT field, depth 2 off the element)
##   - a local declared AFTER those statements — the frame-scanner guard: a body scanner that stopped at
##     one of these statement forms would lose this local's slot and silently mis-address it
##   - neighbour element / neighbour index / neighbour field all read back untouched
## 9 + 8 + 30 + 40 + 7 + 1 + 3 = 98 (< 126, so the WASI proc_exit range holds for the cross-backend sweeps).
Leaf := struct { v : u64, w : u64 }
Row := struct { pad : u64, arr : [u64; 3], inner : Leaf }
main := fn() -> u64 {
  mut xs : [Row; 2]
  xs[0] = Row(pad = 1, arr = [10, 20, 30], inner = Leaf(v = 4, w = 5))
  xs[1] = Row(pad = 2, arr = [40, 50, 60], inner = Leaf(v = 6, w = 7))
  mut i : u64 = 1
  mut j : u64 = 2
  xs[i].arr[j] = 9                       ## runtime i AND runtime j (was 60)
  xs[i].inner.v = 8                      ## deep nested-struct field write on the same element (was 6)
  after : u64 = 3                        ## declared AFTER both deep statements (frame-scanner guard)
  mut r : u64 = 0
  r = r + xs[i].arr[j]                   ## 9  (round-trip of the array-field write)
  r = r + xs[i].inner.v                  ## 8  (round-trip of the nested-field write)
  r = r + xs[0].arr[2]                   ## 30 (neighbour ELEMENT untouched)
  r = r + xs[1].arr[0]                   ## 40 (neighbour INDEX in the written element untouched)
  r = r + xs[1].inner.w                  ## 7  (neighbour FIELD in the written struct untouched)
  r = r + xs[0].pad                      ## 1  (field before the array untouched)
  r = r + after                          ## 3  (the post-declaration local still has its own slot)
  u64(r)
}
