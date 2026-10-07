## e2e — Types §9.1 + Declarations §3.4: an unannotated `0` has no context, so it takes the documented
## default, the target's native SIGNED integer, and the loop counter is an `i64`. Its compare with the
## `usize` length is then a signed/unsigned pair, which Types §4.2/§4.3 refuse: a literal that needs a
## non-default type with no context MUST be annotated or constructed.
main := fn() -> u64 {
  xs : [u64; 3] = [10, 20, 12]
  s := xs[0..3]
  mut acc : u64 = 0
  mut i := 0
  while i < s.len { acc = acc + s[i]; i = i + 1 }
  acc
}
