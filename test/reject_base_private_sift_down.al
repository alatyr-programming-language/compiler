## Issue #524 over-reach control — `sift_down` (lib/base/slice.al) is the heapsort inner step, an
## internal helper of `sort`/`sort_by`. It is named by no Stdlib appendix code block, so Modules
## §3:90-92 keeps it out of the public API and a qualified reference from outside `base::slice` stays
## refused even though `Slice` itself is published by #524.
##
## Self-proving: line 11 calls the PUBLIC `base::slice::sort` on the same slice and is accepted (it
## sorts, so `lib/base/slice.al` is injected and the path resolves); only line 12 is refused.
main := fn() -> u64 {
  mut arr : [u64; 3] = [3, 1, 2]
  s := arr[0..3]
  base::slice::sort(u64, s)
  base::slice::sift_down(u64, s, 3, 0)
  42
}
