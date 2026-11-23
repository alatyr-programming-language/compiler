## Issue #1859 — a `#` line comment is trivia (Grammar §2.5), so a comment between a local's name and
## its `:` leaves the annotation in place: `v` is `[u64; 2]` and its elements are `u64`. The source
## recovery skipped blanks but not comments, read `v` as unannotated, and refused the `u64` sum as a
## signedness mismatch. A comment after the type of an uninitialized local ends the type too: `w` is a
## `u64`, not a type spelled `u64 # the sum`.
main := fn() -> u64 {
  v # the pair
    : [u64; 2] = [40, 2]
  mut w : u64 # the sum
  w = v[0] + v[1]
  w
}
## spec: Grammar §2.5, §2.6; Types §6.4
## expect: run 42
