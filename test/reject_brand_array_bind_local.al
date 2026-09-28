## Issue #698 — the whole-array crossing found beside the parameter one, at an annotated BINDING:
## `ys : [A; 2] = bs` for `bs : [B; 2]`. The parent ran it to 22 (the sibling values under `A`). Refused
## by the same element-type judgement.
A := brand(u64)
B := brand(u64)
main := fn() -> u64 {
  b : B = B(2)
  c : B = B(3)
  bs : [B; 2] = [b, c]
  ys : [A; 2] = bs
  return u64(ys[0]) + u64(ys[1]) * 10
}
