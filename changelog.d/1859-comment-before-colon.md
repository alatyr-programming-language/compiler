- **A `#` comment between a local's name and its `:` no longer drops the type annotation (#1859).**
  `v # note` / `: [u64; 2] = [40, 2]` was checked as unannotated and refused, and with `= deref(p)`
  it copied one word, so `v.len` answered 0 on x86_64. A comment after an uninitialized local's type
  no longer becomes part of the type either.
