## e2e — #937: copying a FIXED array into an annotated local copies the WHOLE `N`-element block.
## Regression for a SILENT WRONG VALUE (I11) on x86_64: `ys : [u64; 3] = xs` reserved `ys` as ONE
## scalar word and stored ONE word, so `ys`'s element addresses ran up into `xs`'s own frame block and
## `ys[i]` answered `xs[i-1]`. MEASURED on the parent: c1d `ys[1] + ys[2]` = **12** where `[5,7,9]`
## owes 16, and c1c `ys[1]` after `xs[1] = 1` = **5** — two spellings of one defect; the reassignment
## form `dst = wr` was wrong the same way. aarch64 and riscv64 answered 42 already, so the backends
## disagreed on one source. Spec: Types §6.4 (`[T; N]` is `N` contiguous elements, `N` a compile-time
## value) and Memory §5.9 ("Ordinary values are copied by default… an aggregate is copied byte-for-byte
## by a documented rule"). A later store to `xs` cannot reach `ys`: a shared view is a slice, not an
## array binding. AGGREGATE- and BYTE-element arrays are the same rule and sit in
## `fixed_array_copy_local_wide.al`, which is x86_64-only today (#1191).
main := fn() -> u64 {
  ## c1d — the copy itself
  xs : [u64; 3] = [5, 7, 9]
  ys : [u64; 3] = xs
  if ys[0] != 5 { return 1 }
  if ys[1] + ys[2] != 16 { return 2 }        ## the issue's own assertion (was 12)

  ## c1c — a copy, not an alias
  mut mu : [u64; 3] = [5, 7, 9]
  cp : [u64; 3] = mu
  mu[1] = 1
  if cp[1] != 7 { return 3 }                 ## the copy must not follow the source (was 5)
  if mu[1] != 1 { return 4 }

  ## the whole block is the destination's own: writing `ys` must not reach `xs`
  mut wr : [u64; 3] = [1, 2, 3]
  mut dst : [u64; 3] = [0, 0, 0]
  dst = wr                                  ## the reassignment form of the same copy
  wr[0] = 9
  if dst[0] != 1 { return 5 }
  if dst[2] != 3 { return 6 }

  ## the source keeps its own value (the copy read the block, it did not take it)
  if xs[0] + xs[1] + xs[2] != 21 { return 7 }

  42
}
## expect: run 42
