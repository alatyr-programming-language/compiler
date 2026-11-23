## Issue #1869 — the elements of an array initialized on the next line are read by index, and a
## comment line between the type and the `=` is trivia (Grammar §2.5). Refused at check before the fix.
main := fn() -> u64 {
  v : [u64; 2]
    = [40, 2]
  w : [u64; 2]
    # the second pair
    = [30, 2]
  v[0] + v[1] + v.len + w[0] + w[1] + w.len - 36
}
## spec: Grammar §2.5, §2.6; Types §6.4
## expect: run 42
